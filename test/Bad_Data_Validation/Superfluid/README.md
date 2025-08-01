---
title: Superfluid
type: Exploit
network: [polygon]
date: 2022-02-08
returned_usd: 0
tags: [data validation]
subcategory: N/A
vulnerable_contracts:
  - "0x3E14dC1b13c488a8d5D310918780c983bD5982E7"
tokens_lost:
  - QI
  - WETH
  - USDC
  - MATIC
attacker_addresses:
  - "0x32D47ba0aFfC9569298d4598f7Bf8348Ce8DA6D4"
  - "0x1574f7f4c9d3aca2ebce918e5d19d18ae853c090"
malicious_token: N/A
attack_block: 24685148
reproduction_command: forge test --match-contract Exploit_Superfluid -vvv
attack_txs:
  - "0x396b6ee91216cf6e7c89f0c6044dfc97e84647f5007a658ca899040471ab4d67"
sources:
  - title: Superfluid Twitter
    url: https://twitter.com/Superfluid_HQ/status/1491045880107048962
  - title: Superfluid Writeup
    url: https://medium.com/superfluid-blog/08-02-22-exploit-post-mortem-15ff9c97cdd
  - title: Rekt Article
    url: https://rekt.news/superfluid-rekt/
---

## Step-by-step

1. Craft a `Context` with a forged `msg.sender`
2. Get it authorized via the host contract

## Detailed Description

This attack relies on a problem in the serialization of the `ctx` in the `Host` contract. To understand this, we need to know that `Superfluid.sol` allows composing `agreements` from different `Super Apps` in a single transaction.

To mantain a state throught the different calls to different `Supper Apps`, this `ctx` is set by the `Host` contract.

Nevertheless, it was possible for the attacker to construct an initial `ctx` that impersonated any user.

The problem can be seen in the [updateSubscription method](https://github.com/superfluid-finance/protocol-monorepo/blob/d04426e7d6950ae9a27d0c50debb7aab7cac1925/packages/ethereum-contracts/contracts/agreements/InstantDistributionAgreementV1.sol#L466), which uses the `AgreementLibrary` to `authorizeTokenAccess`.

Unfortunately, this method [does not authorize much](https://github.com/superfluid-finance/protocol-monorepo/blob/d04426e7d6950ae9a27d0c50debb7aab7cac1925/packages/ethereum-contracts/contracts/agreements/AgreementLibrary.sol#L39) besides requiring that the call comes from a particular address.

The attacker can now send a crafted message that set's anyone as the [`publisher`](https://github.com/superfluid-finance/protocol-monorepo/blob/d04426e7d6950ae9a27d0c50debb7aab7cac1925/packages/ethereum-contracts/contracts/agreements/InstantDistributionAgreementV1.sol#L483).

## Possible mitigations

- The [`git blame`](https://github.com/superfluid-finance/protocol-monorepo/blame/48f5951c1fb30127a462cce7b16871c435d66e10/packages/ethereum-contracts/contracts/agreements/AgreementLibrary.sol#L43) of this fix is quite straightforward: the `authorizeTokenAccess` has to actually call the `Host` to make sure this context has been aproved by it.
