---
title: Punk Protocol Re-initialize
description: Taking control by re-initializing proxy contracts
type: Exploit
network: [ethereum]
date: 2021-08-10
loss_usd: 8950000
returned_usd: 4950000
tags: [access control, reinitialization]
subcategory: []
vulnerable_contracts:
  - "0x3BC6aA2D25313ad794b2D67f83f21D341cc3f5fb"
  - "0x1F3b04c8c96A31C7920372FFa95371C80A4bfb0D"
  - "0x929cb86046E421abF7e1e02dE7836742654D49d6"
tokens_lost:
  - Punk USDT
  - Punk USDC
  - Punk DAI
attacker_addresses:
  - "0x1D5a56402425C1099497C1AD715A6b56aACcB72B"
malicious_token: []
attack_block: [12995895]
reproduction_command: forge test --match-contract Exploit_Punk -vvv
attack_txs:
  - "0x7604c7dd6e9bcdba8bac277f1f8e7c1e4c6bb57afd4ddf6a16f629e8495a0281"
sources:
  - title: Rekt News Report
    url: https://rekt.news/punkprotocol-rekt
  - title: Postmortem
    url: https://medium.com/punkprotocol/punk-finance-fair-launch-incident-report-984d9e340eb
---

## Step-by-step

1. Call `initialize` to set your own `forge_` address
2. Call `withdrawToForge` to withdraw tokens

## Detailed Description

The Punk protocol pools did not prevent someone from calling `initialize` after
the contracts were already initialized.

The attacker called `initialize` through the proxy and set their own `forge_` address, which allowed them to later call `withdrawToForge`, which, as the name implies, withdraws all the funds to the forge address.

```solidity
    function initialize(
        address forge_,
        address token_,
        address cToken_,
        address comp_,
        address comptroller_,
        address uRouterV2_ ) public {
    }
```

## Possible mitigations

- `initialize` functions should always be protected so they can be called only once
