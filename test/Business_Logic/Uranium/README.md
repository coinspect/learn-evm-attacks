# Uranium
- **Type:** Exploit
- **Network:** Binance Chain 
- **Total lost:** ~$50MM USD in different tokens
- **Category:** Miscalculation
- **Vulnerable contracts:**
- - [0xA08c4571b395f81fBd3755d44eaf9a25C9399a4a](https://bscscan.com/address/0xA08c4571b395f81fBd3755d44eaf9a25C9399a4a)
- **Attack transactions:**
- - [0x5a504fe72ef7fc76dfeb4d979e533af4e23fe37e90b5516186d5787893c37991](https://bscscan.com/tx/0x5a504fe72ef7fc76dfeb4d979e533af4e23fe37e90b5516186d5787893c37991)
- **Attacker Addresses**: 
- - EOA: [0xc47bdd0a852a88a019385ea3ff57cf8de79f019d](https://bscscan.com/address/0xc47bdd0a852a88a019385ea3ff57cf8de79f019d)
- - Contract: [0x2b528a28451e9853F51616f3B0f6D82Af8bEA6Ae](https://bscscan.com/address/0x2b528a28451e9853F51616f3B0f6D82Af8bEA6Ae)
- **Attack Block:**: 6947154
- **Date:** Apr 28, 2021
- **Reproduce:** `forge test --match-contract Exploit_Uranium -vvv`

## Step-by-step 
1. Request a swap but without having payed for it

## Detailed Description

This attack resulted from an incorrect calculation in the contant product calculation, popular in Automated Market Makers.

In a constant product AMM, the most important invariant is: `x * y = k`, where `x`, `y` are assets and `k` a constant. This formula governs all trades: swapping is simply puting some amount of tokens (say, `x`) and receiving the amount of `y` so as to make `k` remain constant. `k` is a constant only in swaps; its value is decided by arbitrageurs that add liquidity to the pool (they put `x` and `y` assets in proportion to their market price). There's tons of literature on AMMs but this should be enought to understand this vulnerability.

A particularity of Uniswap and its forks (like Uranium) is that its `swap()` method is not payable: yo `swap` a token for another, you first simply transfer the tokens to Uniswap and then perform the swap (this is of course only reasonable to do from a smart contract).

Now, the `swap` method of Uranium is supposed to hold `k`, no matter the swap. But when upgrading the contracts, the developers modified the constant which was set to `1000` to `10000` (notices the extra zero). Nevertheless, the constant in the `require()` clause was still set to `1000**2`, the old value.

``` solidity
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        ...

        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = balance0.mul(10000).sub(amount0In.mul(16));
        uint balance1Adjusted = balance1.mul(10000).sub(amount1In.mul(16));
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UraniumSwap: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
```

This require, although might not look like it, is what's preserving `K`: it is checking that the `balanceAdjusted` (the new balance minus the payment amount) is bigger than or equal than the previous balance (it must check for `>=` and not only `==` because actually `constant` product is a bit of an exaggeration: `K` [always increases](https://medium.com/@chiqing/uniswap-v2-explained-beginner-friendly-b5d2cb64fe0f), either due to fees or due to inefficient use of the `swap` formula).

Anyway, this update made the left hand side of the equation (which does `newX * newY`) by 10 fold bigger, while mantaining the right hand side (`oldX * oldY`). This means an attacker can perform swaps and not pay to the pool the corresponding amount of tokens necesary.

## Possible mitigations
1. Make sure invariants in the code are mantained correctly

## Diagrams and graphs

### Class

![class](onering.png)

## Sources and references
- [FrankResearcher Twitter Thread](https://twitter.com/FrankResearcher/status/1387347001172398086?s=20&t=Ki5iBMAXIitQS80Cl6BhSA)
- [Rekt Article](https://rekt.news/uranium-rekt/)
- [Source Code](https://bscscan.com/address/0xA08c4571b395f81fBd3755d44eaf9a25C9399a4a#code)
