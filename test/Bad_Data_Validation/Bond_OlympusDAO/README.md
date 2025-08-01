---
title: Bond Olympus DAO
type: Exploit
network: [ethereum]
date: 2022-10-21
loss_usd: 300000
returned_usd: 300000
tags: [data validation]
subcategory: N/A
vulnerable_contracts:
  - "0x007FE7c498A2Cf30971ad8f2cbC36bd14Ac51156"
tokens_lost:
  - OHM
attacker_addresses:
  - "0x443cf223e209E5A2c08114A2501D8F0f9Ec7d9Be"
  - "0xa29e4fe451ccfa5e7def35188919ad7077a4de8f"
malicious_token: N/A
attack_block: 15794364
reproduction_command: forge test --match-contract Exploit_OlympusDAO -vvv
attack_txs:
  - "0x3ed75df83d907412af874b7998d911fdf990704da87c2b1a8cf95ca5d21504cf"
sources:
  - title: Peckshield Twitter Thread
    url: http://https://twitter.com/peckshield/status/1583416829237526528
  - title: 0xbanky.eth Writeup
    url: https://mirror.xyz/0xbanky.eth/c7G9ZfTB8pzQ5cCMw5UhdFehmR6l0fVqd_B-ZuXz2_o
---

## Step-by-step

1. Craft and deploy a contract so that it passes the requirements.
2. Call `redeem` with the malicious contract as the `token_`

## Detailed Description

The attack relies on an arbitrarily supplied `token_` parameter. The attacker simply needs to construct a malicious contract as the `token_`. Most importantly, it should return a token that has been permitted by the victim contract to move funds when its `_underlying()` method is called.

```solidity
    function redeem(ERC20BondToken token_, uint256 amount_)
    external
    override
    nonReentrant {
        if (uint48(block.timestamp) < token_.expiry())
            revert Teller_TokenNotMatured(token_.expiry());
        token_.burn(msg.sender, amount_);
        token_.underlying().transfer(msg.sender, amount_);
    }
```

The attacker chose to set `_underlying()` to the OHM address.

Luckily for the DAO, the attacker was a whitehack that later returned the funds.

## Possible mitigations

- Implement a whitelist of allowed tokens.
