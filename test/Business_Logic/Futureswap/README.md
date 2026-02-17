---
title: Futureswap
description: Exploiting unit mismatch in fee calculation to drain protocol funds
type: Exploit
network: [arbitrum]
date: 2025-01-10
loss_usd: 395000
returned_usd: 0
tags: [business logic, arithmetic, flashloan]
subcategory: []
vulnerable_contracts: ["0xF7CA7384cc6619866749955065f17beDD3ED80bC"]
tokens_lost:
  - USDC
  - WETH
attacker_addresses:
  - "0xbF6EC059F519B668a309e1b6eCb9a8eA62832d95"
malicious_token: []
attack_block: [419829771]
reproduction_command: forge test --match-contract Exploit_Futureswap -vvv
attack_txs:
  - "0xe1e6aa5332deaf0fa0a3584113c17bedc906148730cbbc73efae16306121687b"
sources:
  - title: An unverified trading/liquidity contract at 0xF7CA…80bC was drained for ~$395k.
    url: https://x.com/nn0b0dyyy/status/2009922304927731717
---

## Step-by-step Overview

Futureswap, a perpetual futures protocol on Arbitrum utilizing Uniswap V3 for liquidity suffered a ~$394K exploit due to a unit mismatch bug in fee calculation. The root cause was that `feeAmount` (expressed in token units) was passed directly to `addFee` function as if it were basis points, allowing attackers to register inflated fee shares and drain protocol funds during position settlement.

The Futureswap exploit unfolded in three phases, exploiting a unit conversion error:

1. **Flashloan Funding:**
   - The attacker flashloaned 500,000 USDC.e from Aave V3 to fund and scale the attack
   - Deployed three auxiliary contracts to open multiple leveraged positions
   - Each auxiliary contract was configured with specific position parameters that was calculated off-chain

2. **Position Manipulation (Fee Poisoning):**
   - Opened multiple LONG positions via auxiliary contracts (0.1 ETH, ~0.3246 ETH, 0.001 ETH)
   - Each `changePosition()` call triggered Uniswap V3 swaps via the protocol
   - The swap callback computed `feeAmount` in token units but passed it to `addFee()` as basis points
   - Example: `feeAmount ≈ 501,676` (token units) became `501,676 bps = 5,016.76%` fee share
   - Opened a SHORT position (-68 ETH with 496,500 USDC collateral) to maximize fee accumulation

3. **Profit Extraction:**
   - Closed the first auxiliary position, triggering settlement with the poisoned fee state
   - The inflated fee shares caused the protocol to overpay the attacker during distribution
   - Withdrew ~894,992 USDC.e from the closed position
   - Repaid the 500,000 USDC.e flashloan plus premium
   - Net profit: ~394,742 USDC.e forwarded to attacker EOA


## Detailed Description

### How Futureswap Works

Futureswap V4 is a decentralized leveraged trading protocol on Arbitrum that operates fundamentally as a lending protocol. Liquidity providers (LPs) deposit funds into internal reserves, which traders borrow to create leveraged positions using Uniswap V3 as the underlying swap mechanism.

**Opening a LONG position:**
1. Trader deposits collateral (e.g., 100 USDC for 10x leverage on ETH)
2. Protocol borrows additional USDC from LP reserves (900 USDC in this case)
3. Total amount (1,000 USDC) is swapped for ETH on Uniswap V3
4. The borrowed amount becomes the trader's debt; the ETH becomes their equity

**Opening a SHORT position:**
1. Trader deposits collateral
2. Protocol borrows ETH from reserves
3. ETH is sold on Uniswap V3 for USDC
4. The borrowed ETH becomes debt; the USDC becomes equity

The protocol charges a 0.05% trade fee plus the 0.05% Uniswap V3 pool fee, totaling approximately 0.1% (~10 basis points) per trade.

### The Core Vulnerability: Unit Mismatch in Fee Calculation

When a user calls `changePosition()`, Futureswap executes swaps on Uniswap V3 to adjust the position. The `uniswapV3SwapCallback()` receives the fee amount from Uniswap:

```solidity
// Inside uniswapV3SwapCallback after swap execution
// feeAmount is returned in TOKEN UNITS (e.g., 501,676 for ~0.5 USDC)

// BUGGY CODE:
feeBasisPoints = feeAmount;  // Direct assignment without conversion!
feeManager.addFee(receiver, feeBasisPoints);  // Interpreted as basis points
```

The issue: `feeAmount` from Uniswap is in absolute token units (e.g., `501,676` = 0.501676 USDC for a 6-decimal token), but `addFee()` expects basis points where `10,000 bps = 100%`.

### Attack Execution Flow

The PoC demonstrates the attack sequence:

```solidity
// Step 1: Flashloan 500,000 USDC from Aave
AAVE_POOL.flashLoanSimple(address(this), address(USDC), 500_000_000_000, "", 0);

// Step 2: Open multiple LONG positions via auxiliary contracts
// Each changePosition() poisons the fee state
USDC.transfer(address(aux_01), 1_000_000_000);  // 1,000 USDC
aux_01.execute();  // Opens LONG 0.1 ETH

USDC.transfer(address(aux_02), 2_000_000_000);  // 2,000 USDC
aux_02.execute();  // Opens LONG ~0.3246 ETH

USDC.transfer(address(aux_03), 500_000_000);   // 500 USDC
aux_03.execute();  // Opens LONG 0.001 ETH

// Step 3: Open massive SHORT to maximize fee manipulation
FUTURESWAP.changePosition(
    -68 ether,           // SHORT 68 ETH
    int256(496_500_000_000),  // 496,500 USDC collateral
    0
);

// Step 4: Close position and extract profit via poisoned fees
aux_01.closePosition(0, -894_992_852_305, 0);  // Withdraws ~894,992 USDC

// Step 5: Repay flashloan, profit ~394,742 USDC
```

### Why Multiple Positions?

The attacker used multiple auxiliary contracts for several reasons:
1. **Fee Accumulation:** Each position change accumulated more fee entries
2. **Position Isolation:** Separate contracts allowed selective closing without affecting other positions
3. **Direction Mixing:** Long and short positions created complex settlement calculations that amplified the fee distribution bug
4. **Pool State Manipulation:** The long positions shift pool reserves, enabling the large 68 ETH short to pass PBL validation


### Attack Parameters Analysis

The hardcoded values in the PoC appear to be optimized for maximum extraction within protocol constraints.

#### Protocol State at Block 419829770 (One Block Before Attack)

| Metric | Value |
|--------|-------|
| ETH Price (Chainlink) | $3,085.34 |
| Futureswap WETH | 99.85 ETH |
| Futureswap USDC | 197,436.75 USDC |
| Aave Available USDC | ~546,596 USDC |

#### Flashloan Availability

Aave V3 on Arbitrum had ~546K USDC available at this block. The 500K flashloan provides a ~46K buffer below the maximum available liquidity. However, increasing the flashloan amount would not increase profit since the constraint is on position size rather than available collateral.

#### Maximum Short Position (68 ETH)

Testing on a fork reveals a boundary at 68 ETH:

| Short Size | Collateral | Result |
|------------|------------|--------|
| 68 ETH | 496,500 USDC | Passes |
| 69 ETH | 496,500 USDC | PBL (Position Below Liquidation) |
| 69 ETH | 499,000 USDC | PBL |
| 70 ETH | 541,500 USDC | PBL |

Even with more collateral, positions exceeding 68 ETH fail PBL validation. This suggests the protocol enforces a maximum position size relative to pool liquidity, independent of margin ratio.

#### Close Amount Calculation

The withdrawal amount `-894,992,852,305` represents the USDC balance remaining in the Futureswap contract after all positions are opened. This value drains the pool's USDC reserves to zero.

#### Profit Source: Initial Reserves + Swap Proceeds

While Futureswap initially held only ~197K USDC, the total extractable amount reached ~895K USDC because opening a 68 ETH short requires the protocol to sell ETH on Uniswap V3:

| Source | Amount |
|--------|--------|
| Initial Futureswap USDC | ~197,437 USDC |
| Deposited collateral (all positions) | 500,000 USDC |
| USDC received from selling 68 ETH | ~197,556 USDC |
| **Total pool USDC after positions** | **~894,993 USDC** |

The ~395K profit equals the extracted amount minus the flashloan repayment (~500K + premium). The 68 ETH represents the maximum extractable position: 67 ETH would leave approximately 42K USDC unextracted, while 69 ETH fails protocol validation.


## Conclusions

The Futureswap exploit demonstrates how a unit mismatch bug can lead to the draining of protocol funds, ~$395K from LP reserves. This issue would have been caught by unit testing, since executing the fee flow with a non-zero fee amount reveals a fee percentage orders of magnitude higher than expected.

## Possible Mitigations

A basic unit test exercising the `changePosition()` flow with non-zero fee values would have surfaced the issue. In addition to unit testing, adopting fuzz testing would reduce the likelihood of similar bugs. Separately, the following mitigations would have prevented this exploit:

### 1. Explicit Unit Conversion

- **Normalize Fees:** Convert token unit fees to basis points using the actual trade size as denominator. This ensures fees are always expressed as a percentage of the trade, capped at reasonable values.


### 2. Input Validation and Sanity Checks

- **Cap Fee Values:** Enforce maximum bounds on fee percentages. Futureswap's documented fee is 0.05% (~5 bps) plus Uniswap's 0.05% (~5 bps). Any fee value exceeding ~100 bps (1%) should trigger a revert as it would indicate an error or manipulation.

- **Validate Fee Pool:** Before distribution, verify that total claimed fees don't exceed actual collected fees.

## Sources and References

- [nn0b0dyyy on X - Initial Report](https://x.com/nn0b0dyyy/status/2009922304927731717)
- [Arbiscan - Attack Transaction](https://arbiscan.io/tx/0xe1e6aa5332deaf0fa0a3584113c17bedc906148730cbbc73efae16306121687b)

## Related

- [Uranium](/learn-evm-attacks/cases/uranium/) - Arithmetic error in core AMM constant calculation
- [MobiusDAO](/learn-evm-attacks/cases/mobiusdao/) - Decimal precision error inflates minted token amounts
- [1inch Calldata Corruption](/learn-evm-attacks/cases/1inch-calldata-corruption/) - Encoding/arithmetic error in low-level assembly
