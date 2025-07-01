# MobiusDAO

- **Type:** Exploit
- **Network:** BSC
- **Total lost:** ~2.15MM
- **Category:** Bad Arithmetic
- **Vulnerable contracts:**
- - [Exploited Contract](https://bscscan.com/address/0x95e92b09b89cf31fa9f1eca4109a85f88eb08531) (Unverified Implementation)
- **Tokens Lost**
- - ~9.7 Quadrillion MBU

- **Attack transactions:**
- - [Attack Tx](https://bscscan.com/tx/0x2a65254b41b42f39331a0bcc9f893518d6b106e80d9a476b8ca3816325f4a150)

- - Deployer EOA: [0xB32A53Af96F7735D47F4b76C525BD5Eb02B42600](https://bscscan.com/address/0xB32A53Af96F7735D47F4b76C525BD5Eb02B42600)

- **Attack Block:**: 49470430
- **Date:** May 11, 2025
- **Reproduce:** `forge test --match-contract Exploit_MobiusDAO -vvv`

## Step-by-step Overview

1. Set up a malicious contract
2. Call MobiusDAO's `deposit` function through the exploit contract with 0.001 WBNB
3. Receive over 9.7 quadrillion tokens
4. Swap the tokens for USDT using PancakeSwapV2

## Detailed Description

Decimal precision is critical when performing arithmetic operations between tokens in smart contracts. In the case of MobiusDAO, a miscalculation involving decimals resulted in a severe vulnerability that ultimately led to a loss of approximately $2.15 million. The contract involved was not verified on-chain and, based on its behavior, was likely not audited either.

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
3. Avoid multiplying already 18-decimal price values by 10**18 again
4. Include unit tests that use mock tokens with varying decimals (e.g., 6, 8, 18) to catch conversion errors across different token standards.

## Sources and references

- [Blockaid Twitter Thread](https://x.com/blockaid_/status/1921476644092452922)
- [Quill Audits Exploit Breakdown](https://www.quillaudits.com/blog/hack-analysis/mobius-token-exploit-breakdown)

