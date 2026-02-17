---
title: Bad Guys NFT
description: Claiming unlimited NFTs through unvalidated mint amounts
type: Exploit
network: [ethereum]
date: 2022-09-02
returned_usd: 0
tags: [data validation]
subcategory: []
vulnerable_contracts:
  - "0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac"
tokens_lost:
  - 400 NFT
attacker_addresses:
  - "0xBD8A137E79C90063cd5C0DB3Dbabd5CA2eC7e83e"
malicious_token: []
attack_block: [15460094]
reproduction_command: forge test --match-contract Exploit_Bad_Guys_NFT -vvv
attack_txs:
  - "0xb613c68b00c532fe9b28a50a91c021d61a98d907d0217ab9b44cd8d6ae441d9f"
sources:
  - title: RugDoctorApe Twitter Thread
    url: https://twitter.com/RugDoctorApe/status/1565739119606890498
---

## Step-by-step

1. Get whitelisted
2. Call the whitelist mint function with a high number of `chosenAmount` so you mint all available NFTs.

## Detailed Description

The attacker claimed 400 NFTs in a single transaction. The mistake is in the `WhiteListMint` function, where anyone whitelisted can pass an arbitrary `chosenAmount`. The `_numberMinted_` map is only updated after calling the function, so the `require` passes for any number on the first try.

```solidity
    function WhiteListMint(bytes32[] calldata _merkleProof, uint256 chosenAmount)
        public
    {
        require(_numberMinted(msg.sender)<1, "Already Claimed");
        require(isPaused == false, "turn on minting");
        require(
            chosenAmount > 0,
            "Number Of Tokens Can Not Be Less Than Or Equal To 0"
        );
        require(
            totalSupply() + chosenAmount <= maxsupply - reserve,
            "all tokens have been minted"
        );
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(_merkleProof, rootHash, leaf),
            "Invalid Proof"
        );
        _safeMint(msg.sender, chosenAmount);
    }


```

## Possible mitigations

- The `chosenAmount` parameter seems to be useless and would better be a constant of `1` if that was the intended usage.
- Otherwise, if it was intended to allow for more than one mint per accoutn, restrict the `chosenAmount` parameter.

## Related

- [Sandbox Public Burn](/learn-evm-attacks/cases/sandbox-public-burn/) - Insufficient validation on user-supplied parameters
- [Fantasm Finance](/learn-evm-attacks/cases/fantasm-finance/) - Missing validation on mint allows minting without backing
