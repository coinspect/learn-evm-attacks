# MobiusDAO

- **Type:** Exploit
- **Network:** BSC
- **Total lost:** ~2.15MM
- **Category:** Bad Arithmetic
- **Vulnerable contracts:**
- - [Exploited Contract](https://bscscan.com/address/0x95e92b09b89cf31fa9f1eca4109a85f88eb08531) (Unverified Implementation)
- **Tokens Lost**
- - 

- **Attack transactions:**
- - [Attack Tx](https://bscscan.com/tx/0x2a65254b41b42f39331a0bcc9f893518d6b106e80d9a476b8ca3816325f4a150)

- - Deployer EOA: [0xB32A53Af96F7735D47F4b76C525BD5Eb02B42600](https://bscscan.com/address/0xB32A53Af96F7735D47F4b76C525BD5Eb02B42600)

- **Attack Block:**: 49470430
- **Date:** May 11, 2025
- **Reproduce:** `forge test --match-contract Exploit_MobiusDAO -vvv`

## Step-by-step Overview

1. Call MobiusDAO's `deposit` function through the exploit contract with 0.001 WBNB
2. Receive over 9.7 quadrillion tokens
3. Swap the tokens for USDT using PancakeSwapV2

## Detailed Description


```solidity

```


## Possible mitigations

1. 

## Sources and references

- [Source](https://link_to_source)

