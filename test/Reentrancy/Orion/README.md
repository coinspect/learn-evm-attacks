# Orion Protocol
- **Type:** Exploit
- **Network:** Ethereum
- **Total lost**: ~$3MM
- **Category:** Reentrancy
- **Exploited contracts:**
- - Orion: https://etherscan.io/address/0xb5599f568D3f3e6113B286d010d2BCa40A7745AA
- - Implementation: https://etherscan.io/address/0xc99d22d4d27304d72bab7ad4379833c029bc105c
- **Attack transactions:**
- - Attack Tx: https://etherscan.io/tx/0xa6f63fcb6bec8818864d96a5b1bb19e8bd85ee37b2cc916412e720988440b2aa
- **Attack Block:**: 16542148
- **Date:** Feb 2, 2023
- **Reproduce:** `forge test --match-contract Exploit_Orion -vvv`

## Step-by-step 
1. Deploy ATK token
2. Create uniswap pairs betwwen USDC and ATK, and USDT and ATK
3. Small funding of previous contracts
4. Flashloan USDT
4. Swap values through [USDC, ATK, USDT] path
6. During swap, deposit assets into Orion contract
7. Withdraw and repay flashloan

## Detailed Description
The `swapThroughOrionPool` possess a `nonReentrant` modifier that is missing in the `depositAsset` function. 

```solidity
    function depositAsset(address assetAddress, uint112 amount) external {
        uint256 actualAmount = IERC20(assetAddress).balanceOf(address(this));
        IERC20(assetAddress).safeTransferFrom(
            msg.sender,
            address(this),
            uint256(amount)
        );
        actualAmount = IERC20(assetAddress).balanceOf(address(this)) - actualAmount;
        require(actualAmount <= amount, "IDA");
        generalDeposit(assetAddress, uint112(actualAmount));
    }
```

```
    function swapThroughOrionPool(
        uint112     amount_spend,
        uint112     amount_receive,
        address[]   calldata path,
        bool        is_exact_spend
    ) public payable nonReentrant {
        bool isCheckPosition = LibPool.doSwapThroughOrionPool(
            IPoolFunctionality.SwapData({
                amount_spend: amount_spend,
                amount_receive: amount_receive,
                is_exact_spend: is_exact_spend,
                supportingFee: false,
                path: path,
                orionpool_router: _orionpoolRouter,
                isInContractTrade: false,
                isSentETHEnough: false,
                isFromWallet: false,
                asset_spend: address(0)
            }),
            assetBalances, liabilities);
        if (isCheckPosition) {
            require(checkPosition(msg.sender), "E1PS");
        }
    }
```

Using a custom token it is possible to call the `depositAsset` function from the `swapThroughOrionPool` call.

Additionally, the `swapThroughOrionPool` works by checking balances previous and post the transfer. This allows the user to call `depositAsset` from the swap call and increase its balance in the pool by both the real `depositAsset` call and the additional value counted after the `_swap` method. This actually multiplies the earned amount. 

## Additional observations

We should a possible reduction on the flashloan cost of the attack by requesting a lower amount and performing multiple reentrancies attacks instead of only one with a huge amount

The attack starts with $1 in USDT and doubles each time in a loop call. 

## Possible mitigations
- Use a reentrancy check in the deposit function
- Better track balances by checking transfer call changes instead of the whole function delta
- Balances increases could be bounded by delta value and expected amount for an additional layer of security


## Sources and references
- [Peckshield Twitter Thread](https://twitter.com/peckshield/status/1621337925228306433)
