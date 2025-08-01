---
title: MobiusDAO
type: Exploit
network: [binance smart chain]
date: 2025-05-11
loss_usd: 2150000
returned_usd: 0
tags: [business logic, arithmetic]
subcategory: N/A
vulnerable_contracts:
  - "0x95e92b09b89cf31fa9f1eca4109a85f88eb08531"
tokens_lost:
  - MBU
attacker_addresses:
  - "0xB32A53Af96F7735D47F4b76C525BD5Eb02B42600"
malicious_token: N/A
attack_block: 49470430
reproduction_command: forge test --match-contract Exploit_MobiusDAO -vvv
attack_txs:
  - "0x2a65254b41b42f39331a0bcc9f893518d6b106e80d9a476b8ca3816325f4a150"
sources:
  - title: Blockaid Twitter Thread
    url: https://x.com/blockaid_/status/1921476644092452922
  - title: Quill Audits Exploit Breakdown
    url: https://www.quillaudits.com/blog/hack-analysis/mobius-token-exploit-breakdown
---

## Step-by-step Overview

1. Call MobiusDAO's `deposit` function with 0.001 WBNB
2. Function `0x38d0` converts WBNB amount to USD value using BNB price (18 decimals)
3. Function `0x31ee` incorrectly multiplies this USD value by 10^18 again
4. The inflated value is divided by the actual BNB price
5. Receive over 9.7 quadrillion MBU tokens, resulting in 10^18 times more MBU tokens than intended
6. Swaps the tokens for USDT using PancakeSwapV2

## Detailed Description

An arithmetic error in the token minting calculation resulted in a severe vulnerability that led to a loss of approximately $2.15 million. The contract incorrectly applied an additional 10^18 multiplier to an already properly scaled price value. The contract involved was not verified.

The vulnerability lies in the `deposit` function, which is responsible for minting MBU tokens in exchange for assets like WBNB or USDT. When WBNB is used, the number of MBU tokens to mint is calculated through a chain of internal calls that involves functions `0x38d0` and `0x31ee`.

```solidity
function deposit(address _userAddress, uint256 _wantAmt) public nonPayable {
    //...

    v3 = 0x38d0(_userAddress, _wantAmt);
    require(v3);
    v4 = 0x31ee(_userAddress, v3);

    //...

    v8, /* uint256 */ v9 = address(stor_6).mint(msg.sender, v4).gas(msg.gas);

    //...

    emit Deposit(_userAddress, _wantAmt, v3, v4);
    return v4;
}
```

In function `0x38d0`, the contract checks whether the input token is WBNB. If so, it queries the current BNB price in USDT using `_swapHelper.getBNBPriceInUSDT()`. This function correctly returns a price with 18 decimals.

```solidity
function 0x38d0(address varg0, uint256 varg1) private {
    if (varg0 == address(_usdt)) {
        return varg1;
    } else if (address(_wbnb) == varg0) {
        v0, v1 = address(_swapHelper).getBNBPriceInUSDT().gas(msg.gas);

        //...

        return v1 * varg1;
    } else {
        return 0;
    }
}
```

However, the critical mistake occurs in function `0x31ee`. Instead of using the result from `0x38d0` as-is, the function multiplies the already 18-decimal price again by 10\*\*18, introducing a massive scaling error. The final amount of tokens to be minted is then calculated by dividing this inflated value by the actual price (still 18 decimals), effectively minting 10\*\*18 times more tokens than intended.

```solidity
function 0x31ee(address varg0, uint256 varg1) private {
    //...

    v0, v1 = address(_swapHelper).staticcall(0x769b6f3000000000000000000000000000000000000000000000000000000000).gas(msg.gas);

    //...

    return varg1 * 10 ** 18 / v1;
}
```

This bug means that by simply calling `deposit` with a small amount of WBNB, an attacker could receive an enormous amount of MBU tokens essentially for free.

Because the `mint` function is eventually called with the inflated amount, the attacker was able to receive over 9.7 quadrillion MBU tokens in exchange for just 0.001 WBNB. These tokens were then successfully swapped for USDT on PancakeSwap, resulting in a multi-million dollar exploit.

## Possible mitigations

1. Clearly document the expected decimal precision of all inputs and outputs in functions dealing with value conversions or token minting
2. Always verify the output format of external data sources like price oracles to ensure their values are properly scaled before using them in calculations
3. Pay close attention to decimal handling when performing operations involving tokens, ensuring that all calculations correctly account for the token's decimal precision
4. Include unit tests that use mock tokens with varying decimals (e.g., 6, 8, 18) to catch conversion errors across different token standards
