# Wintermute
- **Type:** Exploit
- **Network:** Ethereum 
- **Total lost**: ~160MM USD
- **Category:** Key Leak
- **Vulnerable contracts:**
- - None
- **Attack transactions:**
- - [0xeecba26d5eb7939257e5b3e646e4bc597b73e256a89cb84a6dfc58de250d8a38](https://etherscan.io/tx/0xeecba26d5eb7939257e5b3e646e4bc597b73e256a89cb84a6dfc58de250d8a38)
- **Attacker Addresses**: 
- - EOA: [0x0000000fE6A514a32aBDCDfcc076C85243De899b](https://etherscan.io/address/0x0000000fE6A514a32aBDCDfcc076C85243De899b)
- - Contract: [0x0248F752802B2cfB4373cc0c3bC3964429385c26](https://etherscan.io/address/0x0248F752802B2cfB4373cc0c3bC3964429385c26)
- **Attack Block:**: 15572488
- **Date:** Sept 20, 2022 (public disclosure)
- **Reproduce:** `forge test --match-contract Exploit_Wintermute -vvv` 

## Step-by-step 
1. Craft an evil `_bridge` contract
2. Call `initialize` setting the `_bridge` to be your malicious contract.

## Detailed Description

Wintermute had generated the keys os a privileged account using [Profanity](https://github.com/johguse/profanity), which had a [serious vulnerability reported only days before the attack](https://blog.1inch.io/a-vulnerability-disclosed-in-profanity-an-ethereum-vanity-address-tool-68ed7455fc8c).

Once they had access to the private key of the account, the attacker set the 

## Possible mitigations
- Be careful when wiping up slots.
- Be careful when removing "useless" checks.
- Test deploy conditions, like `should not be able to reinitialize contract`

## Sources and references
- [Writeup](https://medium.com/@0xriptide/hackers-in-arbitrums-inbox-ca23272641a2)
