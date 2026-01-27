---
title: "1inch Calldata Corruption"
description: "Exploiting Yul assembly calldata corruption via integer underflow to hijack resolver callbacks and drain funds"
type: Exploit
network: [ethereum]
date: 2025-03-05 
loss_usd: 5000000 
returned_usd: 4490000 
tags: [business logic, data validation, arithmetic]
subcategory: []
vulnerable_contracts:
    - "0xb02f39e382c90160eb816de5e0e428ac771d77b5"
    - "0xa88800cd213da5ae406ce248380802bd53b47647"
tokens_lost:
    - USDC
    - WETH
attacker_addresses: 
    - "0x019BfC71D43c3492926D4A9a6C781F36706970C9"
malicious_token: []
attack_block: [21982111]
attack_txs:
    - "0x62734ce80311e64630a009dd101a967ea0a9c012fabbfce8eac90f0f4ca090d6"
    - "0xb0688eb1f46c28f36d7397366146fced23d3f8da7e08b760a5f612ce134ee9d2"
    - "0x9ce5187c7160f531189e4765f21af5975dc2a62d961fb61ae09866d082918256"
    - "0x3947e5a4d98104e313e08ee321673e1183db3d6ff8b7207f3eabb36f71436c1d"
    - "0x74bc4d5dc7f8da468788da6087bb9f73465966ab5b8cf9cf1053d98e78a9bf96"
    - "0xefcb740bf9ec17ed99839ffcc05393fae5ec2d44149aee91ba119f48bc20a1ef"
    - "0xc69b4c8029c70ae468e92af31120ac6b01bb89c6e35d34818413e9942aedebb6"
    - "0xb16bbf03d324b66685c94d62dbe31c739ee23c114b3915d169c74cd7c98eec8c"
    - "0xb5c94efa0c8fd8f5c8cc2826e374a99620b01061d395b59b8f45dddc9fce1c60"
    - "0x04975648e0db631b0620759ca934861830472678dae82b4bed493f1e1e3ed03a"

reproduction_command: "forge test --match-contract Exploit_OneInch -vvv" 

sources:
  - title: "Decurity Post-Mortem"
    url: "https://blog.decurity.io/yul-calldata-corruption-1inch-postmortem-a7ea7a53bfd9"
  - title: "Rekt News"
    url: "https://rekt.news/1inch-rekt"
  - title: "Attacker Contract Decompiled"
    url: "https://app.dedaub.com/ethereum/address/0x019bfc71d43c3492926d4a9a6c781f36706970c9/decompiled"
---

## Step-by-step


1. **Attacker deploys exploit contract** that implements EIP-1271 signature validation and exposes a `settle()` function that forwards crafted orders to `Settlement.settleOrders()`.

2. **Attacker crafts malicious order payload** containing 6 nested orders  calculated ABI encoding offsets and a negative interaction length value.

3. **Attacker calls `Settlement.settleOrders()`** which processes the nested order chain recursively through `_settleOrder()`.

4. **Integer underflow corrupts suffix write location** when the vulnerable Yul assembly calculates where to write the order suffix, the negative length causes the write position to underflow, writing the legitimate suffix over zero-padding instead of at the end of calldata.

5. **Fake suffix with victim as resolver is read** by the `DynamicSuffix` library, which reads from the end of calldata where the attacker placed a crafted suffix containing the victim's address as the "resolver".

6. **Settlement calls `victim.resolveOrders()`** believing it's the legitimate resolver. Since the caller is the trusted Settlement contract, the victim (TrustedVolumes) transfers funds to the attacker.

7. **Attacker receives ~$5M** across multiple tokens (USDC, WETH) from TrustedVolumes resolver contract.

## Detailed Description

The 1inch Settlement exploit targeted the deprecated Fusion V1 Settlement contract, exploiting a vulnerability in the `_settleOrder()` function. The attack represents a calldata corruption technique.

### Background: 1inch Fusion Architecture

1inch Fusion is a gasless swap protocol where resolvers (market makers) fill user orders. The Settlement contract coordinates order execution by:

1. Processing orders through `settleOrders()` → `_settleOrder()`
2. Appending a "suffix" containing resolver information to each order
3. Calling `resolveOrders()` on the resolver to execute token transfers

The assumption: only the legitimate resolver should be called, and it trusts the Settlement contract as the caller.

### The Vulnerable Code

The vulnerability exists in `_settleOrder()`'s Yul assembly block:
```solidity
function _settleOrder(
    bytes calldata data, 
    address resolver, 
    uint256 totalFee, 
    bytes memory tokensAndAmounts
) private {
    // ... order validation ...
    
    assembly {
        // [1] Read interaction offset from attacker-controlled calldata
        let interactionLengthOffset := calldataload(add(data.offset, 0x40))
        let interactionOffset := add(interactionLengthOffset, 0x20)
        
        // [2] Read interaction length
        let interactionLength := calldataload(add(data.offset, interactionLengthOffset))
        
        // ... copy calldata to memory at 'ptr' ...
        
        // [3] Calculate suffix write position - Underflow 
        let offset := add(add(ptr, interactionOffset), interactionLength)
        
        // [4] Write suffix data including resolver address
        mstore(add(offset, 0x04), totalFee)
        mstore(add(offset, 0x24), resolver)    // <-- Resolver written here
        mstore(add(offset, 0x44), takerAsset)
        // ... more suffix fields ...
    }
}
```

The code trusts `interactionLength` from calldata without validation. By providing a massive value (`0xFFFF...FE00` = `-512` in two's complement), the offset calculation underflows, causing the suffix to be written in memory.

### Attack Mechanics

#### Phase 1: Crafting the Malicious Payload

The attacker constructs a nested order chain with 6 orders. The malicious calldata uses standard ABI-encoded pointers: order offset at `0xE0`, signature offset at `0x240`, and interaction offset at `0x460`.

After the 320-byte order struct, the attacker places 544 bytes of zero-padding (`0x260`-`0x460`), then at `0x460` places `-512` as `uint256` instead of a legitimate interaction length. At `0x480`, the fake suffix contains the victim's address as resolver.

#### Phase 2: The Underflow Calculation

When `_settleOrder()` processes this data:
```
Normal calculation:
  offset = ptr + interactionOffset + interactionLength
         = ptr + 0x480 + positive_value
         = writes at END of calldata ✓

Attack calculation:
  offset = ptr + interactionOffset + (-512)
         = ptr + 0x480 - 0x200
         = ptr + 0x280
         = writes EARLIER, over zero padding ✗
```

The legitimate suffix (with the correct resolver = attacker's contract) gets written to the zero-padding region and is ignored. Meanwhile, the `DynamicSuffix` library reads from the end of calldata, where the attacker placed their fake suffix.

#### Phase 3: Resolver Hijacking

The fake suffix structure:
```solidity
bytes memory victimSuffix = abi.encode(
    uint256(0),           // totalFee (padding)
    RESOLVER,             // resolver ← THE VICTIM ADDRESS!
    address(USDC),        // takerAsset
    uint256(0),           // rateBump (padding)
    uint256(0),           // takingFee (padding)
    address(USDC),        // token
    DRAIN_AMOUNT,         // amount to steal
    uint256(0x40)         // tokensAndAmounts length
);
```

When Settlement processes the finalize interaction:
```solidity
// Settlement thinks resolver = VICTIM (from fake suffix)
// Calls: VICTIM.resolveOrders(VICTIM, tokensAndAmounts, data)
// VICTIM sees msg.sender = Settlement (trusted!) → transfers funds
```

### Why 6 Nested Orders?

Each nested order adds entries to the internal `tokensAndAmounts` array. The attacker needed sufficient entries so that:
```
suffixSize = staticFields (160 bytes) + tokensAndAmounts (~320 bytes) + length (32 bytes)
           ≈ 512 bytes (0x200)
```

This makes the `-512` offset calculation precisely rewind the write position over the zero-padding.

### Interaction Flags

The Settlement contract uses single-byte flags to control flow:
```solidity
// From fillOrderInteraction()
if (interaction[20] == 0x00) {
    // CONTINUE: Process next nested order
    _settleOrder(interaction[21:], ...);
} else if (interaction[20] == 0x01) {
    // FINALIZE: Call resolver.resolveOrders()
    target.resolveOrders(resolver, tokensAndAmounts, data);
}
```

Orders 1-5 use `0x00` (continue) to build the chain. Order 6 uses `0x01` (finalize) to trigger the drain.


## Conclusions

The 1inch Settlement exploit represents a rare class of smart contract vulnerability memory corruption in Yul assembly. Several factors contributed to its success:

1. **Deprecated but live code**: Fusion V1 was deprecated in mid-2023 but remained deployed for backward compatibility, receiving no security updates.

2. **Complex interaction patterns**: The nested order mechanism, created attack surface that single-order analysis couldn't reveal.

3. **Trusted caller assumption**: The victim resolver trusted Settlement as the caller without validating the resolver parameter in the suffix.

The attack was executed across 10 transactions, draining approximately $5M total from the `TrustedVolumes` resolver. Our PoC reproduces one representative transaction stealing 1M USDC. After on-chain negotiation, most funds were returned, with the attacker keeping a fractional bounty.

## Possible Mitigations

### 1. Input Validation in Assembly

Validate that `interactionLength` does not exceed `data.length` before using it in offset calculations.

### 2. Safe Arithmetic for Offset Calculations

Implement overflow checks on pointer arithmetic in Yul assembly to prevent underflow from negative values.

### 3. Resolver Self-Validation

Resolver contracts should verify the `resolver` parameter matches their own address, not just trust the Settlement caller.
