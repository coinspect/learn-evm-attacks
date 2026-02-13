# The Balancer V2 Rate Manipulation Attack: Technical Analysis

## Executive Summary

On August 27, 2023, Balancer V2 pools suffered an attack resulting in approximately $2 million in losses. The attacker exploited rounding errors in the `StableSwap` invariant calculation to manipulate BPT (Balancer Pool Token) prices. This writeup provides a technical analysis based on transaction traces, decompiled contracts, and the actual vulnerability in the Balancer V2 codebase.

## Table of Contents
1. [Background](#background)
2. [The Vulnerability](#the-vulnerability)
3. [Attack Analysis](#attack-analysis)
4. [Technical Implementation Details](#technical-implementation-details)
5. [Impact and Lessons Learned](#impact-and-lessons-learned)
6. [Conclusion](#conclusion)
7. [References](#references)

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

### Root Cause

The vulnerability exists in `StableMath.sol` ([balancer-v2-monorepo](https://github.com/balancer/balancer-v2-monorepo/blob/88842344fb5f44d8ed6f8f944acd3be80627df87/pkg/pool-stable/contracts/StableMath.sol#L25)) where the invariant calculation accumulates rounding errors through consistent use of `divDown`:

```solidity
// StableMath.sol - Invariant calculation with divDown
// Line 91:
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

### How the Vulnerability Works

The vulnerability stems from three key factors:
1. **Rounding Direction**: Consistent use of `divDown` and `mulDown` causes errors to accumulate in one direction
2. **Token Scaling**: Precision loss when scaling token amounts with different decimals
3. **BPT Price Formula**: Since `BPT price = invariant (D) / totalSupply`, manipulating D directly impacts BPT price

When token balances are manipulated to specific values (e.g., `cbETH = 9`), the rounding errors become significant enough to artificially deflate the BPT price. The **Batch Swap Capability** then enables the execution of complex swap sequences in a single transaction, allowing the rate manipulation to be executed atomically.

## Attack Analysis

### Phase 1: Discovery and Parameter Search

**Transaction**: `0x6ed07db1a9fe5c0794d44cd36081d6a6df103fab868cdd75d581e3bd23bc9742`

The attacker deployed two contracts to systematically discover optimal exploitation parameters:
- **SC1 (Coordinator)**: `0x54b53503C0e2173DF29f8da735Fbd45ee8ABA30D`
- **SC2 (Math Helper)**: `0x679b362b9f38be63fbd4a499413141a997eb381e`

The search process:
1. SC1 repeatedly calls SC2's function `0x524c9e20` with varying balance parameters
2. SC2 simulates pool calculations to test for maximum precision loss
3. ~30% of calls revert with `BAL#004` when hitting division edge cases (indicating boundary testing)
4. SC1 identifies parameters that maximize rounding errors

### Phase 2: Execution and Manipulation

Within the same transaction, the attacker executes a carefully orchestrated batch swap following a three-step pattern:

1. **Setup Swaps**: Swap BPT for underlying assets to manipulate token balances to rounding boundaries
   - Example: Setting `cbETH = 9` to position at edge case

2. **Exploitation Swaps**: Execute swaps between tokens using amounts that trigger maximum rounding errors
   - Based on [analysis](https://x.com/Phalcon_xyz/status/1985302779263643915), using amount `= 8`:
   - Computed `Δx` rounds down: `8.918 → 8`
   - This leads to underestimated `Δy`
   - Invariant D becomes artificially smaller
   - BPT price deflates since `BPT price = D / totalSupply`

3. **Extraction Swaps**: Reverse-swap underlyings back to BPT at the deflated price
   - Profits from the difference between manipulated and actual rates

### Phase 3: Value Extraction

**Transaction**: `0xd155207261712c35fa3d472ed1e51bfcd816e616dd4f517fa5959836f5b48569`

After manipulating the rates, the attacker extracts value:
- **Method**: `manageUserBalance` to withdraw from internal balances
- **Extracted Assets**:
  - 6,587 WETH
  - 6,851 osETH
  - 4,259 wstETH
- **Total Value**: ~$2 million

The manipulated rates allowed arbitrage between the artificially inflated pool rates and actual market rates.

## Technical Implementation Details

### Attacker's Smart Contracts

#### SC2 (Math Helper) - Function 0x524c9e20

The decompiled bytecode reveals a function designed to identify exploitable parameters:

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

The function deliberately creates zero denominators to test pool calculation boundaries, explaining the ~30% revert rate observed in transaction traces.

#### SC1 (Coordinator) - Attack Orchestration

The coordinator contract manages the entire attack flow:

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

### Batch Swap Implementation

The batch swap execution is carefully sized to:
- Stay below individual slippage limits
- Compound rounding errors in the attacker's favor
- Execute all operations atomically within a single transaction

## Impact and Lessons Learned

### Technical Innovations

This attack introduced several sophisticated techniques:

1. **On-chain Parameter Search**: Deployed contracts that systematically searched for exploitable parameters through trial and error
2. **Rounding Error Exploitation**: Identified specific balance values that maximize precision loss in StableSwap calculations
3. **Batch Swap Orchestration**: Used complex swap sequences to compound rounding errors in a single atomic transaction

### Key Technical Insights

1. **Rounding Accumulation**: Consistent use of `divDown` in `StableMath.sol` allowed errors to compound in one direction
2. **Edge Case Discovery**: The search algorithm found that specific balances (like `cbETH=9`) trigger maximum precision loss
3. **Batch Swap Power**: The ability to execute complex swap sequences in one transaction enabled the exploitation

### Defensive Measures

Following the attack, several mitigations were identified:

1. **Rounding Direction**: Mix `divUp` and `divDown` to prevent unidirectional error accumulation
2. **Minimum Balance Requirements**: Prevent manipulation to extremely low values
3. **Rate Change Limits**: Implement circuit breakers for abnormal BPT price movements
4. **Invariant Validation**: Add additional checks on invariant calculations

## Conclusion

The Balancer V2 attack demonstrates how mathematical edge cases in DeFi protocols can be systematically discovered and exploited. The attacker's use of on-chain search algorithms to find optimal exploitation parameters represents an evolution in attack sophistication.

The vulnerability stemmed from the accumulation of rounding errors when token balances were manipulated to specific values. By setting balances to rounding boundaries and executing calculated swaps, the attacker could deflate BPT prices and extract value through arbitrage.

This incident highlights that:
- Mathematical models must consider precision loss at edge cases
- Consistent rounding directions can create exploitable biases
- Complex features like batch swaps require careful security analysis
- Attackers are developing increasingly sophisticated exploitation techniques

## References

- Attack Transactions: [0x6ed07db...](https://etherscan.io/tx/0x6ed07db1a9fe5c0794d44cd36081d6a6df103fab868cdd75d581e3bd23bc9742), [0xd155207...](https://etherscan.io/tx/0xd155207261712c35fa3d472ed1e51bfcd816e616dd4f517fa5959836f5b48569)
- Balancer V2 Monorepo: [github.com/balancer/balancer-v2-monorepo](https://github.com/balancer/balancer-v2-monorepo)
- Vulnerability Analysis: [@Phalcon_xyz](https://x.com/Phalcon_xyz/status/1985302779263643915)
- Balancer Documentation: [docs.balancer.fi](https://docs.balancer.fi)

---

*This analysis is for educational and security research purposes only. The code and techniques described should not be used for malicious purposes.*

*If you find vulnerabilities in DeFi protocols, please follow responsible disclosure practices and report them to the respective teams.*