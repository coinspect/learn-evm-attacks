---
####################################################################
# Please fill out the template below when documenting a new attack #
####################################################################

title: "Attack Name Here" # title: z.string()
description: "Brief description of what happened in the attack - how the vulnerability was exploited" # description: z.string().optional()
type: Exploit # type: z.string(),
# Names with images in the website: ethereum, polygon, binance smart chain, moonbeam, gnosis chain, fantom, arbitrum
network: ["ethereum"] # network: z.array(z.string())
date: 2023-01-01 # date: z.coerce.date() /Format: YYYY-MM-DD/
loss_usd: 0 # loss_usd: z.number().min(0).default(0)
returned_usd: 0 # returned_usd: z.number().min(0).default(0)
tags: ["reentrancy"] # tags: z.array(z.string())
subcategory: [] # subcategory: z.array(z.string()).optional()
vulnerable_contracts: # vulnerable_contracts: z.array(z.string()),
    - "0xCONTRACT_ADDRESS_HERE"
tokens_lost: # tokens_lost: z.array(z.string()).optional()
    - "TOKEN_SYMBOL"
attacker_addresses: # attacker_addresses: z.array(z.string())
    - "0xATTACKER_ADDRESS_HERE"
malicious_token: [] # malicious_token: z.array(z.string()).optional()
attack_block: [123456789] # attack_block: z.array(z.number())
attack_txs: # attack_txs: z.array(z.string())
    - "0xTRANSACTION_HASH_HERE"
reproduction_command: "forge test --match-contract Exploit_ProjectName -vvv" # reproduction_command: z.string(),

sources:
    # sources: z.array(
    #   z.object({
    #     title: z.string(),
    #     url: z.string()
    #   })
    # )
    - title: "Source Title Here"
      url: "https://example.com"
---

## Step-by-step

1. [First step of the attack]
2. [Second step of the attack]
3. [Third step of the attack]

## Detailed Description

[Detailed explanation of how the attack worked, including:]

-   [The vulnerability that was exploited]
-   [How the attacker identified and exploited it]
-   [Technical details about the exploit mechanism]
-   [Any relevant code snippets showing the vulnerable function]

```solidity
// Example vulnerable code
function vulnerableFunction() external {
    // Show the problematic code here
}
```

[Explain why this code was vulnerable and how it was exploited]

## Possible mitigations

-   [Mitigation strategy 1]
-   [Mitigation strategy 2]
-   [Mitigation strategy 3]

## Additional Notes

[Any additional context, lessons learned, or important details about this attack]
