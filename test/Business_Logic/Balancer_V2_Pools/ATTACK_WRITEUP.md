# The Balancer V2 Rate Manipulation Attack: Technical Analysis

## Executive Summary

On August 27, 2023, Balancer V2 pools suffered an attack resulting in approximately $2 million in losses. The attacker exploited rounding errors in the `StableSwap` invariant calculation to manipulate BPT (Balancer Pool Token) prices. This writeup provides a technical analysis based on transaction traces, decompiled contracts, and the actual vulnerability in the Balancer V2 codebase.

## Table of Contents
1. [Background](#background)
2. [The Vulnerability](#the-vulnerability)
3. [Attack Methodology](#attack-methodology)
4. [Technical Deep Dive](#technical-deep-dive)
5. [The Search Algorithm](#the-search-algorithm)
6. [The Extraction Pattern](#the-extraction-pattern)
7. [Impact and Lessons Learned](#impact-and-lessons-learned)

## Background

### Balancer V2 Architecture

Balancer V2 is an automated market maker (AMM) that uses a vault architecture where:
- All tokens are held in a central **Vault** contract
- Individual **Pools** contain the logic for trading and pricing
- Pools use **cached rates** for gas efficiency
- **Batch swaps** allow multiple trades in a single transaction

### The Targeted Pools

Two pools were exploited:
1. **osETH/WETH-BPT** (Pool ID: `0xdacf5fa19b1f720111609043ac67a9818262850c...635`)
   - Starting rate: `1.027e18`
   - Ending rate: `20.189e18` (1,864% increase!)

2. **wstETH/WETH-BPT** (Pool ID: `0x93d199263632a4ef4bb438f1feb99e57b4b5f0bd...5c2`)
   - Starting rate: `1.051e18`
   - Ending rate: `3.887e18` (270% increase!)

## The Vulnerability

The vulnerability stems from precision loss in the StableSwap invariant calculation, specifically in how Balancer's `StableMath.sol` handles rounding:

1. **Rounding Direction**: The use of `divDown` and `mulDown` in invariant calculations
2. **Token Scaling**: Precision loss when scaling token amounts with different decimals
3. **BPT Price Formula**: `BPT price = invariant (D) / totalSupply`

The attack then uses the **Batch Swap Capability**, which allows the execution of chained swap sequences, enabling the rate manipulation in a single transaction.

### The Root Cause

At `StableMath.sol` ([balancer-v2-monorepo](https://github.com/balancer/balancer-v2-monorepo/blob/88842344fb5f44d8ed6f8f944acd3be80627df87/pkg/pool-stable/contracts/StableMath.sol#L25)), there was an issue where the invariant calculation accumulates rounding errors:

```solidity
// StableMath.sol - Invariant calculation with divDown
D_P = Math.divDown(Math.mul(D_P, invariant), Math.mul(balances[j], numTokens));
invariant = Math.divDown(...);  // Multiple divDown operations compound precision loss
```

When token balances are manipulated to specific values (e.g., `cbETH = 9`), the rounding errors become significant enough to artificially deflate the BPT price.

## Attack Methodology

### Phase 1: Parameter Search

The attacker deployed two contracts:
- **SC1 (Coordinator)**: `0x54b53503C0e2173DF29f8da735Fbd45ee8ABA30D`
- **SC2 (Math Helper)**: `0x679b362b9f38be63fbd4a499413141a997eb381e`

The search process involved SC1 repeatedly calling SC2's function `0x524c9e20` to find parameters that would maximize rounding errors:

1. SC1 calls SC2 with varying balance parameters
2. SC2 simulates pool calculations to test for maximum precision loss
3. Some calls revert with `BAL#004` when hitting division edge cases
4. SC1 reads return values to identify optimal manipulation parameters

### Phase 2: Execution

The attack execution followed a three-step pattern within a single batch swap:

1. **Setup Phase**: Swap BPT for underlying assets to manipulate one token balance to a rounding boundary
2. **Exploitation Phase**: Execute swaps between tokens using amounts that trigger maximum rounding errors
3. **Extraction Phase**: Reverse-swap underlyings back to BPT, profiting from the deflated BPT price

### Phase 4: Value Extraction

The manipulated rates allowed the attacker to extract significant value through arbitrage between the artificially inflated pool rates and actual market rates.

## Technical Deep Dive

### Decompiled Contract Analysis

Analysis of the attacker's decompiled contracts reveals sophisticated preparation:

#### SC2 (Math Helper) - Function 0x524c9e20

The decompiled bytecode shows this function performs math calculations to identify exploitable parameters:

```solidity
// Decompiled from 0x679b362b9f38be63fbd4a499413141a997eb381e
function unknown524c9e20(
    uint256[] calldata scalingFactors,
    uint256[] calldata balances,
    uint256 indexIn,
    uint256 indexOut,
    uint256 amountGiven,
    uint256 normalizedWeight,
    uint256 swapFeePercentage
) external returns (uint256) {
    // Scale balances according to scaling factors
    for (uint256 i = 0; i < balances.length; i++) {
        adjustedBalances[i] = _upscale(balances[i], scalingFactors[i]);
    }

    // Manipulate calculation to approach zero under specific conditions
    uint256 virtualBalance = adjustedBalances[indexOut] - adjustedBalances[indexOut]; // = 0

    // Calculate denominator that approaches zero
    uint256 feeAdjustedWeight = _mulDown(normalizedWeight, _complement(swapFeePercentage));
    uint256 denominator = (virtualBalance + feeAdjustedWeight) - (virtualBalance + feeAdjustedWeight); // = 0

    // This operation triggers BAL#004 when conditions are met
    return _divDown(weightedProduct, denominator);
}
```

The function deliberately creates zero denominators to test pool calculation boundaries. The ~30% revert rate in transaction traces indicates the systematic exploration of edge cases.

#### SC1 (Coordinator) - Main Attack Logic

The coordinator contract orchestrates the entire attack:

```solidity
// Decompiled pattern from 0x54b53503C0e2173DF29f8da735Fbd45ee8ABA30D
contract AttackCoordinator {
    // Storage slots reveal complex state tracking
    address[] private targetPools;      // slot 0x17
    uint256 public attackParam1;        // slot 0x31
    uint256 public attackParam2;        // slot 0x32

    function execute8a4f75d6(address[] calldata pools) external {
        for (uint256 j = 0; j < pools.length; j++) {
            // Get pool tokens and approve vault
            (tokens, balances) = vault.getPoolTokens(poolId);

            // Search for exploitable parameters
            for (uint256 i = 0; i < iterations; i++) {
                try mathHelper.unknown524c9e20(...) returns (uint256 score) {
                    if (score > bestScore) {
                        optimalParams = currentParams;
                    }
                }
            }

            // Execute batch swap with discovered parameters
            vault.batchSwap(SwapKind.GIVEN_IN, swaps, ...);
        }
    }
}
```

### The Rounding Exploitation Mechanism

Based on transaction analysis and the [tweet](https://x.com/Phalcon_xyz/status/1985302779263643915) from `@Phalcon_xyz`, the attack exploits rounding in three steps:

1. **Balance Manipulation**: Swap `BPT` for underlying assets to set one token (e.g., `cbETH`) to a specific amount (`= 9`) at the edge of a rounding boundary

2. **Precision Loss Trigger**: Execute a swap between tokens with a crafted amount (`= 8`). Due to `divDown` in scaling:
   - Computed `Δx` rounds down: `8.918 → 8`
   - This leads to underestimated `Δy`
   - Invariant D becomes artificially smaller
   - Since `BPT price = D / totalSupply`, the BPT price deflates

3. **Value Extraction**: Reverse-swap underlying assets back to BPT at the deflated price, extracting the value difference

## The Search Algorithm

The search algorithm systematically explores parameter space to find maximum rounding error conditions.

The ~30% revert rate observed in traces indicates the algorithm is testing boundary conditions where calculations approach division by zero, precisely where rounding errors are maximized.

## Attack Execution Pattern

The batch swap execution follows a calculated pattern to maximize extraction:

1. **Setup swaps**: Manipulate balances to rounding boundaries
2. **Exploitation swaps**: Trigger maximum precision loss
3. **Extraction swaps**: Convert deflated BPT back to underlying assets

Each swap is sized to:
- Stay below individual slippage limits
- Compound rounding errors in the attacker's favor


## Attack Transactions

### Transaction 1: Parameter Search & Manipulation
**Hash**: `0x6ed07db1a9fe5c0794d44cd36081d6a6df103fab868cdd75d581e3bd23bc9742`

- **Search Phase**: Multiple calls to SC2 function `0x524c9e20`
- **Revert Pattern**: ~30% of calls revert with `BAL#004`
- **Execution**: Batch swap with discovered parameters
- **Result**: BPT prices manipulated through rounding errors

### Transaction 2: Value Extraction
**Hash**: `0xd155207261712c35fa3d472ed1e51bfcd816e616dd4f517fa5959836f5b48569`

- **Method**: `manageUserBalance` to withdraw from internal balances
- **Extracted**: 6,587 WETH, 6,851 osETH, 4,259 wstETH
- **Total Value**: ~$2 million

## Vulnerability in Balancer Codebase

The vulnerability exists in these locations within the Balancer V2 codebase:

### StableMath.sol

```solidity
// Line 91: Invariant calculation with consistent divDown
D_P = Math.divDown(Math.mul(D_P, invariant), Math.mul(balances[j], numTokens));

// Line 96-104: Multiple divDown operations compound precision loss
invariant = Math.divDown(
    Math.mul(
        Math.divDown(Math.mul(ampTimesTotal, sum), _AMP_PRECISION).add(Math.mul(D_P, numTokens)),
        invariant
    ),
    Math.divDown(Math.mul((ampTimesTotal - _AMP_PRECISION), invariant), _AMP_PRECISION).add(
        Math.mul((numTokens + 1), D_P)
    )
);
```

The use of `divDown` (rounding down) means errors accumulate in one direction. When balances are manipulated to specific values, these errors become large enough to significantly impact the BPT price calculation.

## Impact and Lessons Learned

### The Attack's Innovation

This attack introduced several technical innovations:

1. **On-chain Parameter Search**: The attacker deployed contracts that systematically searched for exploitable parameters through trial and error
2. **Rounding Error Exploitation**: Identified specific balance values that maximize precision loss in StableSwap calculations
3. **Batch Swap Orchestration**: Used complex swap sequences to compound rounding errors

### Defensive Measures

Following the attack, several mitigations were identified:

1. **Rounding Direction**: Mix `divUp` and `divDown` to prevent unidirectional error accumulation
2. **Minimum Balance Requirements**: Prevent manipulation to extremely low values
3. **Rate Change Limits**: Circuit breakers for abnormal BPT price movements
4. **Invariant Validation**: Additional checks on invariant calculations

### Key Technical Insights

1. **Rounding Accumulation**: Consistent use of `divDown` in `StableMath.sol` allowed errors to compound in one direction
2. **Edge Case Discovery**: The search algorithm found that balances like `cbETH=9` trigger maximum precision loss
3. **Batch Swap Power**: The ability to execute complex swap sequences in one transaction enabled the exploitation


## Conclusion

The Balancer V2 attack demonstrates how mathematical edge cases in DeFi protocols can be systematically discovered and exploited. The attacker's use of on-chain search algorithms to find optimal exploitation parameters represents an evolution in attack sophistication.

The vulnerability stemmed from the accumulation of rounding errors when token balances were manipulated to specific values. By setting balances to rounding boundaries and executing calculated swaps, the attacker could deflate `BPT` prices and extract value through arbitrage.

This incident highlights that:
- Mathematical models must consider precision loss at edge cases
- Consistent rounding directions can create exploitable biases
- Complex features like batch swaps require careful security analysis
- Attackers are developing and getting better in their exploitation techniques

## References

- Attack Transactions: [0x6ed07db...](https://etherscan.io/tx/0x6ed07db1a9fe5c0794d44cd36081d6a6df103fab868cdd75d581e3bd23bc9742), [0xd155207...](https://etherscan.io/tx/0xd155207261712c35fa3d472ed1e51bfcd816e616dd4f517fa5959836f5b48569)
- Balancer V2 Monorepo: [github.com/balancer/balancer-v2-monorepo](https://github.com/balancer/balancer-v2-monorepo)
- Vulnerability Analysis: [@Phalcon_xyz](https://x.com/Phalcon_xyz/status/1985302779263643915)
- Balancer Documentation: [docs.balancer.fi](https://docs.balancer.fi)

---

*This analysis is for educational and security research purposes only. The code and techniques described should not be used for malicious purposes.*

*If you find vulnerabilities in DeFi protocols, please follow responsible disclosure practices and report them to the respective teams.*