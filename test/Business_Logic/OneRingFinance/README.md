---
title: One Ring Finance
description: Exploiting share price manipulation via reserve balance changes
type: Exploit
network: [Fantom]
date: 2022-03-21
loss_usd: 1550000
returned_usd: 0
tags: [business logic, price manipulation]
subcategory: []
vulnerable_contracts:
  - "0x66a13cd7ea0ba9eb4c16d9951f410008f7be3a10"
tokens_lost:
  - USDC
attacker_addresses:
  - "0x12efed3512ea7b76f79bcde4a387216c7bce905e"
  - "0x6a6d593ed7458b8213fa71f1adc4a9e5fd0b5a58"
malicious_token: []
attack_block: [34041500]
reproduction_command: forge test --match-contract Exploit_OneRingFinance -vvv
attack_txs:
  - "0xca8dd33850e29cf138c8382e17a19e77d7331b57c7a8451648788bbb26a70145"
sources:
  - title: Writeup
    url: https://medium.com/oneringfinance/onering-finance-exploit-post-mortem-after-oshare-hack-602a529db99b
---

## Step-by-step

1. Flashloan some USDC
2. Deposit it to mint shares
3. Withdraw the shares for USDC
4. Repay loand and transfer profit

## Detailed Description

One Ring Finance used the amount of reserves held in the vault as a price gauge. The attacker can manipulate the price by changhing the amount of reserves in the contract.

Both the `deposit` and `withdraw` methods use:

```solidity
        uint256 _sharePrice = getSharePrice();
```

To calculate how many shares the user must receive. To exploit this, the attacker deposited USDC into the contract, which drove the price of the shares up, and then immediatly sold them.

## Possible mitigations

1. Use Time-Weighted price feeds or other reliable oracles to get the price of commodities instead of relying on a metric that can be manipulated with flash loans.
2. Another strategy is to implement `slippage`, so the price of each share increase the more you buy.
