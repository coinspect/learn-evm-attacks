---
title: BVaults
type: Exploit
network: [binance smart chain]
date: 2022-10-30
loss_usd: 35000
returned_usd: 0
tags: [business logic, price manipulation]
subcategory: N/A
vulnerable_contracts:
  - "0xB2B1DC3204ee8899d6575F419e72B53E370F6B20"
tokens_lost:
  - WBNB
attacker_addresses:
  - "0x5bfaa396c6fb7278024c6d7230b17d97ce8ab62d"
malicious_token: N/A
attack_block: 22629432
reproduction_command: forge test --match-contract Exploit_BVaults -vvv
attack_txs:
  - "0xe7b7c974e51d8bca3617f927f86bf907a25991fe654f457991cbf656b190fe94"
sources:
  - title: Beosin Alert's Twitter
    url: https://twitter.com/BeosinAlert/status/1588579143830343683
  - title: Source Code
    url: https://bscscan.com/address/0xb2b1dc3204ee8899d6575f419e72b53e370f6b20#code
---

## Step-by-step

1. Create a malicious token and pair
2. Inflate its price
3. Call convertDustToEarned
4. Swap again
5. Cashout and repeat

## Detailed Description

This attack relies on the fack that BVault provided a `convertDustToEarned` method that would swap all of the tokens in the pool to "earned" tokens.

Unfortunately, it did not do any kind of price check or use any kind of smoothing of the price curve. This makes it vulnerable to price inflation: the attacker created a malicious token and pair, inflated the price of the token in the pool and then used it to gain `earnedTokens`.

```solidity
    function convertDustToEarned() public whenNotPaused {
        require(isAutoComp, "!isAutoComp");

        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

        // Converts token0 dust (if any) to earned tokens
        uint256 _token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Address != earnedAddress && _token0Amt > 0) {
            _vswapSwapToken(token0Address, earnedAddress, _token0Amt);
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 _token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Address != earnedAddress && _token1Amt > 0) {
            _vswapSwapToken(token1Address, earnedAddress, _token1Amt);
        }
    }

    function _vswapSwapToken(address _inputToken, address _outputToken, uint256 _amount) internal {
        IERC20(_inputToken).safeIncreaseAllowance(vswapRouterAddress, _amount);
        IValueLiquidRouter(vswapRouterAddress).swapExactTokensForTokens(_inputToken, _outputToken, _amount, 1, vswapPaths[_inputToken][_outputToken], address(this), now.add(1800));
    }
```

## Possible mitigations

- Either introduce an oracle to get a second-source of truth for prices or use time-weighted-average to smooth the curve.
