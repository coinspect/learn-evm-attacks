---
title: TempleDAO Spoof Old Staking Contract
type: Exploit
network: [ethereum]
date: 2022-10-11
loss_usd: 2300000
returned_usd: 0
tags: [access control]
subcategory: []
vulnerable_contracts:
  - "0xd2869042E12a3506100af1D192b5b04D65137941"
tokens_lost:
  - TEMPLE
  - FRAX
attacker_addresses:
  - "0x9c9Fb3100A2a521985F0c47DE3B4598dafD25B01"
malicious_token: []
attack_block: [15725067]
reproduction_command: forge test --match-contract Exploit_TempleDAO -vvv
attack_txs:
  - "0x8c3f442fc6d640a6ff3ea0b12be64f1d4609ea94edd2966f42c01cd9bdcf04b5"
sources:
  - title: BlockSecTeam Twitter Thread
    url: https://twitter.com/BlockSecTeam/status/1579843881893769222
---

## Step-by-step

1. Create a contract that does not revert when receiving a call to `migrateWithdraw`
2. Call `migrateStake(evilContract, MAX_UINT256)` and get a lot of tokens.

## Detailed Description

The protocol wanted to allow users to migrate stake from an old contract to a new one. To do that, they provided a `migrateStake` function:

```solidity
    function migrateStake(address oldStaking, uint256 amount) external {
        StaxLPStaking(oldStaking).migrateWithdraw(msg.sender, amount);
        _applyStake(msg.sender, amount);
    }
```

An OK implementation of `migrateWithdraw` should transfer `amount` from `msg.sender` to the current contract and revert if it wasn't able to. `_applyStake` would later add `amount` to `msg.sender`.

Unfortunately, it is trivial to pass an evil `oldStaking` contract that never reverts.

## Possible mitigations

- Store a list of valid `oldStaking` contract addresses and whitelist them (needs an `owner` if the list needs to be dynamic)
