---
title: Balancer V2 Stable Pools Rate Manipulation
description: Rounding inconsistency in stable invariant calculation deflates BPT price via crafted batchSwap sequence
type: Exploit
network: [ethereum]
date: 2025-11-03
loss_usd: 128000000
returned_usd: 0
tags: [business logic]
subcategory: [Rate Manipulation]
vulnerable_contracts:
  - "0xDACf5Fa19b1f720111609043ac67A9818262850c"
  - "0x93d199263632a4EF4Bb438F1feB99e57b4b5f0BD"
  - "0xBA12222222228d8Ba445958a75a0704d566BF2C8"
tokens_lost:
  - WETH
  - osETH
  - wstETH
attacker_addresses: ["0x506D1f9EFe24f0d47853aDca907EB8d89AE03207"]
attack_block: [23717396]
reproduction_command: forge test --match-contract Exploit_Balancer_V2_Pools -vvv
attack_txs:
  - "0x6ed07db1a9fe5c0794d44cd36081d6a6df103fab868cdd75d581e3bd23bc9742"
  - "0xd155207261712c35fa3d472ed1e51bfcd816e616dd4f517fa5959836f5b48569"
sources:
  - title: Balancer V2 Stable Pools Exploit — Rate Manipulation (Coinspect)
    url: https://www.coinspect.com/blog/balancer-rate-manipulation-exploit/
---

# Balancer V2 Stable Pools Rate Manipulation

## Attack Overview

On November 3, 2025, an attacker manipulated exchange rates in Balancer V2 Composable Stable Pools by issuing a long, alternating batchSwap sequence that exploited rounding inconsistencies in the stable invariant calculation. The attack deflated the invariant D, reducing the implied BPT price and allowing the attacker to extract value through arbitrage. Stolen funds exceeded USD 128 million. The incident affected Composable Stable Pools across Ethereum, Base, Avalanche, Gnosis, Polygon, Arbitrum, and Optimism. Balancer V3 and other pool types were unaffected.

## Root Cause

The vulnerability stems from a rounding inconsistency between scaling operations:

- **Upscaling**: Uses unidirectional rounding (always rounds down via `mulDown`)
- **Downscaling**: Uses bidirectional rounding (`divUp` or `divDown` depending on context)

This violates the principle that rounding should always favor the protocol. In `GIVEN_OUT` swaps, `_upscale()` incorrectly rounds down the output amount, leading to underestimation of the required input.

The stable invariant calculation compounds the error through repeated `divDown` operations:

```solidity
// StableMath.sol - Invariant calculation with divDown
D_P = Math.divDown(Math.mul(D_P, invariant), Math.mul(balances[j], numTokens));
invariant = Math.divDown(...);  // Multiple divDown operations compound precision loss
```

Because BPT price scales with `D / totalSupply`, a lower D yields a lower implied BPT price than the balances warrant. Mixed token decimals amplify the precision loss. The batchSwap's deferred settlement allows maintaining manipulated balances within a single call, bypassing minimum pool supply limits.

## Attack Method

The attack used a two-stage approach with two deployed contracts:

- **SC1 — Coordinator** (`0x54b53...a30d`): Orchestrates the attack. Reads `getPoolTokens`, identifies indices (BPT, WETH, other), runs parameter probes, builds `BatchSwapStep[]`, submits `batchSwap`, and later calls `manageUserBalance` to extract value.
- **SC2 — Math Helper** (`0x679b3...381e`): Computes stable-invariant-related expressions over scaled balances. Edge inputs drive denominators toward zero; reverts such as `BAL#004` (division by zero) mark boundaries.

### Stage 1 — Boundary Search (Parameter Calculation)

SC1 performed a binary search using on-chain feedback from SC2:
- Iterate over candidate inputs (balance deltas, scaling/amount values)
- When SC2 completes: keep the candidate (safe region)
- When SC2 reverts with `BAL#004`: treat as boundary signal and adjust
- This converges on values where rounding effects are largest

### Stage 2 — Rate Manipulation (Batch Swap)

Using the tuned candidates, SC1 constructed a single `batchSwap` with three operation types in an alternating 4-leg block pattern:
1. **Setup**: Swap BPT for underlying assets to position tokens at rounding boundaries
2. **Manipulation**: Execute calculated swaps that trigger precision loss, deflating D
3. **Profit setup**: Reverse-swap underlying assets back to BPT at the manipulated rate

### Stage 3 — Value Extraction (Separate Transaction)

With internal balances credited from the first transaction, SC1 invoked `manageUserBalance(WITHDRAW_INTERNAL)` for each asset, then transferred tokens to the attacker EOA.

## Observed Effects

Two pools showed large rate movements between BPT and underlying tokens:

| Pool | Before | After | Change |
|------|--------|-------|--------|
| osETH/WETH-BPT (`0xDACf5...850c`) | ~1.027e18 | ~20.189e18 | +1,864% |
| wstETH/WETH-BPT (`0x93d19...f0BD`) | ~1.051e18 | ~3.887e18 | +270% |

## Files in This Reproduction

- `AttackCoordinator.sol` — Main orchestrator (SC1)
- `BalancerExploitMath.sol` — Mathematical exploit contract (SC2)
- `Balancer_V2_Pools.attack.sol` — Test harness
- `Interfaces.sol` — Required interfaces
- `SC1_decompiled.sol` — Decompiled attacker coordinator
- `SC2_decompiled.sol` — Decompiled exploit math contract

## Running the Test

```bash
forge test --match-contract Exploit_Balancer_V2_Pools -vvv
```

## Mitigation

- Enforce consistent protocol-favoring rounding directions across all scaling operations
- Ensure `_upscale()` rounds in the correct direction for `GIVEN_OUT` swaps
- Add bounds checking on invariant D changes between operations
- Limit cumulative rounding drift within a single batchSwap call
