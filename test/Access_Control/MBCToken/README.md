---
title: MBC Token
type: Exploit
network: [binance smart chain]
date: 2022-11-29
loss_usd: 5000
returned_usd: 0
tags: [access control]
subcategory: []
vulnerable_contracts:
  - "0x4E87880A72f6896E7e0a635A5838fFc89b13bd17"
  - "0xeE04a3f9795897fd74b7F04Bb299Ba25521606e6"
tokens_lost:
  - MBC
attacker_addresses:
  - "0x0b13D2B0d8571C3e8689158F6DB1eedf6E9602d3"

malicious_token: []
attack_block: [23474461]
reproduction_command: forge test --match-contract Exploit_MBCToken -vvv
attack_txs:
  - "0xdc53a6b5bf8e2962cf0e0eada6451f10956f4c0845a3ce134ddb050365f15c86"
sources:
  - title: Ancilia Twitter Thread
    url: https://twitter.com/AnciliaInc/status/1597742575623888896
  - title: Contract Source Code
    url: https://bscscan.com/address/0x4E87880A72f6896E7e0a635A5838fFc89b13bd17#code
---

## Step-by-step

1. Request a flash loan
2. Swap all `MBC` for `BUSD` (after this, the price of `MBC` will be inflated in the pool)
3. Now call `swapAndLiquifyStepV1`, which will add a certain amount of `MBC` and `BUSD` to the pool
4. Exchange the `MBC` you gained in (2) for the `BUSD` now in the pool. The pool belives `MBC` to be very valuable so gives you a lot of `BUSD`.
5. Repay flash loan.
6. Keep the rest.

## Detailed Description

Understanding this attack needs a small prior on [Uniswap router contracts](https://docs.uniswap.org/contracts/v2/reference/smart-contracts/router-02) and their methods.

Routers are contracts that facilitate the interaction with Uniswap pools. An important function in a router is `addLiquidity`:

```solidity
function addLiquidity(
  address tokenA,
  address tokenB,
  uint amountADesired,
  uint amountBDesired,
  uint amountAMin,
  uint amountBMin,
  address to,
  uint deadline
) external returns (uint amountA, uint amountB, uint liquidity);
```

This will try to add liquidity to the pool where trades of `tokenA/tokenB` happen. `amountADesired/amountBDesired` is the ideal amount of `A` and `B` to add, while `amountAMin/amountBMin` works as slippage protection.

With that in mind, we can check the MBC Token `swapAndLiquifyStepv1()` function:

```solidity
    function swapAndLiquifyStepv1() public {
        uint256 ethBalance = ETH.balanceOf(address(this));
        uint256 tokenBalance = balanceOf(address(this));
        addLiquidityUsdt(tokenBalance, ethBalance);
    }

    function addLiquidityUsdt(uint256 tokenAmount, uint256 usdtAmount) private {
        uniswapV2Router.addLiquidity(
            address(_baseToken),
			address(this),
            usdtAmount,
            tokenAmount,
            0,
            0,
            _tokenOwner,
            block.timestamp
        );
    }
```

In this contract, the `_baseToken` is the address [`0x55d398326f99059fF775485246999027B3197955`](https://bscscan.com/address/0x55d398326f99059ff775485246999027b3197955#code), `BUSD Stablecoin`. `ETH` refers to the same `_baseToken`.

Something important here to stress is that the `MBC Token` has a balance of their own (ie: the contract has its own tokens, `balanceOf(address(this)) != 0`) because it charges a fee to users on every transaction.

Now, inmediatly after calling `swapAndLiquifyStepv1`, the contract will go to the `BUSD/MBC` liquidity pool
and add all of its balances of both BUSD and MBC to it.

A small sidenote here, but: why does this contract have this function anyway? It does not seem to do much. The answer appears to be some [controversial tokenomics](https://www.youtube.com/watch?v=CvSJzqwJdBA). We haven't been able to pinpoint who invented it, but [Safemoon](https://safemoon.com/), now facing [lawsuits](https://www.nerdwallet.com/article/investing/safemoon), [seems to swear by it](https://www.safemoon.education/post/swap-and-evolve).

Anyway, moving on the attack. How does the attacker take advantage of this? They inflate the price of the token in the pool and foce the contract to buy it all up.

In the same transaction, they:

1. Request a flash loan
2. Swap all `MBC` for `BUSD` (after this, the price of `MBC` will be inflated in the pool)
3. Now call `swapAndLiquifyStepV1`, which will add a certain amount of `MBC` and `BUSD` to the pool
4. Exchange the `MBC` you gained in (2) for the `BUSD` now in the pool. The pool belives `MBC` to be very valuable so gives you a lot of `BUSD`.
5. Repay flash loan.
6. Keep the rest.

## Possible mitigations

- `swapAndLiquifyStepv1` should be made private
