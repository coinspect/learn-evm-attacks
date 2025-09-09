---
title: Seaman
description: Forcing contracts to trade at manipulated token prices
type: Exploit
network: [binance smart chain]
date: 2022-11-29
loss_usd: 7000
returned_usd: 0
tags: [business logic, price manipulation]
subcategory: []
vulnerable_contracts:
    - "0x6bc9b4976ba6f8c9574326375204ee469993d038"
tokens_lost:
    - GVC
attacker_addresses:
    - "0x4b1f47be1f678076f447585beba025e3a046a9fa"
    - "0x0E647d34c4caF61D9E377a059A01b5C85AB1d82a"
malicious_token: []
attack_block: [23467516]
reproduction_command: forge test --match-contract Exploit_Seaman -vvv
attack_txs:
    - "0x6f1af27d08b10caa7e96ec3d580bf39e29fd5ece00abda7d8955715403bf34a8"
sources:
    - title: Beosin Alert
      url: https://twitter.com/BeosinAlert/status/1597535796621631489
    - title: Source Code
      url: https://bscscan.com/address/0x6bc9b4976ba6f8c9574326375204ee469993d038#code
---

## Step-by-step

1. Flashloan some USDC
2. Use the flashloan to buy all GVC in a pool
3. Call `transfer()` so contract buys GVC at current high price
4. Sell your GVC
5. Return flashloan

## Detailed Description

This is very similar to the attack on [MBC](https://www.coinspect.com/learn-evm-attacks/cases/mbc-token/). It actually involves the same method, `swapAndLiquifyV1`.

Every time someone called `_transfer` on Seaman, the `swapAndLiquify` calls where made. These methods would exchange the accumulated fee on the contract for `GVC`, passing through the `BUSD` pool.

```solidity
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
         // ...
         if( uniswapV2Pair.totalSupply() > 0 && balanceOf(address(this)) > balanceOf(address(uniswapV2Pair)).div(10000) && to == address(uniswapV2Pair)){
            if (
                !swapping &&
                _tokenOwner != from &&
                _tokenOwner != to &&
               !ammPairs[from] &&
                !(from == address(uniswapV2Router) && !ammPairs[to])&&
                swapAndLiquifyEnabled
            ) {
                swapping = true;
                swapAndLiquifyV3();
                swapAndLiquifyV1();
                swapping = false;
            }
        }
       // ...
    }

    function swapAndLiquifyV1() public {
        uint256 canlpAmount = lpAmount.sub(lpTokenAmount);
        uint256 amountT = balanceOf(address(uniswapV2Pair)).div(10000);
        if(balanceOf(address(this)) >= canlpAmount && canlpAmount >= amountT){
            if(canlpAmount >= amountT.mul(5))
                canlpAmount = amountT.mul(5);
            lpTokenAmount = lpTokenAmount.add(canlpAmount);
            uint256 beflpBal = lpToken.balanceOf(address(this));
            swapTokensFor(canlpAmount,address(lpToken),address(this));
            uint256 newlpBal = lpToken.balanceOf(address(this)).sub(beflpBal);
            lpDivTokenAmount = lpDivTokenAmount.add(newlpBal);
            isLpProc = true;
        }
    }

    function swapAndLiquifyV3() public {
        uint256 canhAmount = hAmount.sub(hTokenAmount);
        uint256 amountT = balanceOf(address(uniswapV2Pair)).div(10000);
        if(balanceOf(address(this)) >= canhAmount && canhAmount >= amountT){
            if(canhAmount >= amountT.mul(5))
                canhAmount = amountT.mul(5);
            hTokenAmount = hTokenAmount.add(canhAmount);
            uint256 befhBal = hToken.balanceOf(address(this));
            swapTokensFor(canhAmount,address(hToken),address(this));
            uint256 newhBal = hToken.balanceOf(address(this)).sub(befhBal);
            hDivTokenAmount = hDivTokenAmount.add(newhBal);
            isHProc = true;
        }
    }
```

This makes it possible for an attacker to manipulate the price and force the contract to buy tokens at a high price. In this case, the attacker influenced the price of `GVC` by requesting a flashloan of `BUSD` and buying up all the available liquidity of GVC in the pool and then calling `transfer()` on Seaman.

## Possible mitigations

1. Prevent users to manipulate contract balances via low liquidity pair interactions.
2. Do not automatically perform trades without a sanity check on the prices
