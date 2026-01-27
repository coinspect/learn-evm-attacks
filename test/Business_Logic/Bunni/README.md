---
title: Bunni
description: Exploiting rounding bug in withdrawals to manipulate liquidity
type: Exploit
network: [ethereum, unichain]
date: 2025-09-02
loss_usd: 8400000
returned_usd: 0
tags: [business logic, price manipulation, flashloan, arithmetic]
subcategory: []
vulnerable_contracts: ["0x000000000049C7bcBCa294E63567b4D21EB765f1","0x22AD38AffE86A3D831DF57CB4A3248bD345a4FAE"]
tokens_lost:
  - USDC
  - USDT
  - ETH
  - weETH
attacker_addresses:
  - "0x0C3d8fA7762Ca5225260039ab2d3990C035B458D"
  - "0x6F559f75ba08d7f45a344E12ECBe8BC15A700DdA"
malicious_token: []
attack_block: [23273098]
reproduction_command: forge test --match-contract Exploit_Bunni -vvv
attack_txs:
  - "0x1c27c4d625429acfc0f97e466eda725fd09ebdc77550e529ba4cbdbc33beb97b"
  - "0x4776f31156501dd456664cd3c91662ac8acc78358b9d4fd79337211eb6a1d451"
sources:
  - title: Bunni Post-Mortem 
    url: https://blog.bunni.xyz/posts/exploit-post-mortem/
  - title: Rekt
    url: https://rekt.news/bunni-rekt
  - title: Certik Alert
    url: https://x.com/CertiKAlert/status/1962755574283768308
---

## Step-by-step Overview

 Bunni V2 a liquidity management protocol built as a hook on Uniswap V4 with a custom Liquidity Distribution Function (LDF)—suffered an $8.4M exploit across two pools: `USDC/USDT` on Ethereum ($2.4M) and `weETH/ETH` on Unichain ($5.9M). The root cause was a rounding-direction bug in `BunniHubLogic::withdraw()` that, when exploited through repeated withdrawals, allowed the attacker to reduce the pool's total liquidity calculation. The attack combined flashloan, swaps to manipulate balance ratios, 44 withdrawals to compound rounding errors, and a exploiting the liquidity to extract value.

The Bunni V2 exploit unfolded in three phases, exploiting subtle rounding errors in liquidity management:

1. **Initial Pool Manipulation:**
   - The attacker flashloaned 3M USDT from Uniswap V3 to fund the attack
   - Executed a sequence of three swaps (`USDT→USDC`,` USDC→USDT`, `USDT→USDC`)
   - These swaps pushed the spot price to extreme values
   - The pool's active `USDC` balance was reduced to just 28 wei while maintaining a large idle balance
   - The price movement was enabled by Bunni's carpeted double geometric liquidity distribution

2. **Exploitation Through Repeated Withdrawals (Liquidity Drain):**
   - Performed 44 sized small withdrawals from the LP position
   - Each withdrawal exploited a rounding error in the idle balance update calculation
   - The `mulDiv` operation in `BunniHubLogic::withdraw()` rounded down the idle balance decrease
   - This caused the idle balance to remain artificially high relative to the active balance
   - Active USDC balance was disproportionately reduced from 28 wei to just 4 wei 
   - Total pool liquidity erroneously decreased by 84.4% from `5.83e16` to `9.114e15`
   - The cumulative effect of rounding errors across multiple operations created the vulnerability

3. **Sandwich Attack on Liquidity Increase (Profit Extraction):**
   - Executed a first swap, pushing the tick to `839189`  which corresponds to `1 USDC = 2.77e36 USDT`.
   - The artificially low liquidity from step 2 caused price impact
   - This extreme price caused the liquidity estimation to flip from `totalLiquidityEstimate0` to `totalLiquidityEstimate1`
   - The new estimate `1.065e16` was higher than the manipulated value `9.114e15` but still below the original `5.83e16`
   - Executed The attacker exploited this self-created liquidity rebound by trading at the manipulated prices
   - Executed a second swap for USDT at the inflated price
   - Repaid the 3M USDT flashloan plus fees to Uniswap V3
   - Net profit: `~1.33M` USDC and `~1M` USDT


## Detailed Description


The Bunni exploit represents the cumulative effects of seemingly benign rounding decisions across multiple operations. The attack leveraged three key design characteristics of Bunni's custom Liquidity Distribution Function (LDF):

1. The carpeted double geometric distribution allowing extreme price movements
2. The dual-balance system with insufficient validation
3. The liquidity estimation mechanism that switches between token0 and token1 based estimates

### Phase 1: Active Balance Manipulation Through Swap Sequencing

Bunni pools maintain two distinct balance components:
- **Active Balance**: Liquidity actively providing swap services
- **Idle Balance**: Reserves not currently in the active tick range

The attacker's create a massive imbalance between these two components for `USDC` (token0).
```solidity
// From the PoC - Initial swap sequence
function executeInitialSwapSequence() internal {
    IPoolManager.SwapParams[] memory swapParams = new IPoolManager.SwapParams[](3);
    
    // Swap 1: Small USDT->USDC to test pool state
    swapParams[0] = IPoolManager.SwapParams({
        zeroForOne: false,
        amountSpecified: -17_088106,
        sqrtPriceLimitX96: 79226236828369693485340663719
    });
    
    // Swap 2: Large USDC->USDT to drain active reserves
    swapParams[1] = IPoolManager.SwapParams({
        zeroForOne: false,
        amountSpecified: 1_835_309_634512,
        sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970341
    });
    
    // Swap 3: Small USDT->USDC to finalize manipulation
    swapParams[2] = IPoolManager.SwapParams({
        zeroForOne: false,
        amountSpecified: -1_000000,
        sqrtPriceLimitX96: 101729702841318637793976746270
    });
}
```

After these swaps:
- **Active balance USDC: Only 28 wei**
- The spot tick reached to `1.688` USDT per USDC

By reducing the active balance to nearly zero while maintaining a large idle balance, the attacker created the conditions for exploiting rounding errors in subsequent withdrawals.

### Phase 2: The Rounding Error

The vulnerability resided in this seemingly innocuous line from `BunniHubLogic::withdraw()`:
```solidity
// decrease idle balance proportionally to the amount removed
{
    (uint256 balance, bool isToken0) = IdleBalanceLibrary.fromIdleBalance(state.idleBalance);
    uint256 newBalance = balance - balance.mulDiv(shares, currentTotalSupply); // VULNERABLE LINE
    if (newBalance != balance) {
        s.idleBalance[poolId] = newBalance.toIdleBalance(isToken0);
    }
}
```

The `mulDiv` operation rounds down, which was intended to round up the remaining idle balance. However, when the active balance is extremely small relative to the idle balance, this creates a compounding error.


### Phase 3: Profit Extraction 

With liquidity artificially reduced to `9.114e15`, the attacker executed a two-swap sandwich to extract value:

**Swap 4: Creating Price Impact**

The attacker swapped an enormous amount of USDT for USDC, pushing the price:
```solidity
// Swap 4: Buy USDC with massive USDT amount
swapParams2[0] = IPoolManager.SwapParams({
    zeroForOne: false,
    amountSpecified: -10_000_000_000_000_000000,  // 10 quintillion USDT
    sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970341
});
```

Result:
- Price pushed to tick `839,189` (~`2.78e36` USDT per USDC)
- Received: 1 wei USDC

This extreme price movement caused Bunni's liquidity estimation to flip from using the USDC-based estimate to the USDT-based estimate:

- Before: `totalLiquidity = 9.114e15` 
- After: `totalLiquidity = 1.065e16` 

**Swap 5: Extracting Profit at Inflated Prices**

With prices at extremes but liquidity now higher, the attacker reversed the trade:
```solidity
// Swap 5: Sell USDC for USDT at inflated price
swapParams2[1] = IPoolManager.SwapParams({
    zeroForOne: true,
    amountSpecified: 10_000_002_885_864_344623,
    sqrtPriceLimitX96: 4295128740
});
```

**Final Settlement:**
```solidity
// From the PoC - After both swaps complete
console.log('------- STEP 6: Repay flash loan -------\n');
USDT.safeTransfer(address(pairWethUsdt), FLASH_LOAN_AMOUNT + fee);

console.log('------- FINAL BALANCES -------');
// Final profit: ~1.33M USDC + ~1M USDT after repaying 3M USDT loan
```

## Conclusions beyond the Post-Mortem

The Bunni team's post-mortem identified the cause as incorrect rounding direction in withdrawal logic. However, the rounding directions that appear safe in isolation became erroneous when chained across multiple operations. The protocol's dual liquidity estimation mechanism `totalLiquidityEstimate0` vs `totalLiquidityEstimate1` created an exploitable transition point—the attacker manipulated which estimate was active by pushing prices to extremes, then profited from the switch. Most critically, no invariant checks prevented the active/idle balance ratio from reaching incredible levels. The largest pool on Unichain `USDC/USD₮0` survived only because insufficient flashloan liquidity was available—the attack required `~17M` but Euler's vault held only ~11M.

Bunni's custom Liquidity Distribution Function introduced novel concepts in AMM design, but custom mathematical models inherently increase edge case likelihood. Complex interactions between the LDF, dual balance system, and Uniswap V4 hooks multiplied risk exponentially. Without extensive battle-testing and invariant-based safeguards. 

## Possible Mitigations

Based on the identified vulnerabilities and Bunni's post-mortem analysis, several mitigations can be proposed:

### 1. Rounding Direction

- **Correct Withdrawal Rounding:** The immediate fix identified by Bunni involves changing the rounding direction in `BunniHubLogic::withdraw()` from rounding down to rounding up when calculating idle balance decreases. This prevents the accumulation of artificially inflated idle balances across multiple withdrawals.

### 2. Withdrawal Controls

- **Minimum Withdrawal Sizes:** Prevent micro-withdrawals by enforcing minimum withdrawal amounts unless the user is withdrawing their entire balance. The attacker's 44 tiny withdrawals were specifically sized to compound rounding errors—such operations should trigger safeguards.

### 3. Comprehensive Testing Framework

- **Fuzz Testing:** As Bunni acknowledged, existing Foundry and Medusa fuzz tests failed to cover multi-step manipulation scenarios. Protocols with custom accounting logic must implement extensive fuzz testing and simulations that cover the edge conditions.