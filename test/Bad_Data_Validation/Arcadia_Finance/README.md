# Arcadia Finance

- **Type:** Exploit
- **Network:** Base
- **Total lost:** ~ 3.6 million USD
- **Category:** Data validation
- **Vulnerable contracts:**
    - [Vault](https://arbiscan.io/address/0x489ee077994b6658eafa855c308275ead8097c4a#code)
    - [GLP Manager](https://arbiscan.io/address/0x321f653eed006ad1c29d174e17d96351bde22649#code)

- **Tokens Lost**
    - ~ 9749629 USDC
    

- **Attack transactions:**

    - Setup:

        - Exploit contract calls createIncreaseOrder
        createIncreaseOrder 0
        https://arbiscan.io/tx/0x0b8cd648fb585bc3d421fc02150013eab79e211ef8d1c68100f2820ce90a4712

        - Keeper executes increase order
        executeIncreaseOrder 0
        https://arbiscan.io/tx/0x28a000501ef8e3364b0e7f573256b04b87d9a8e8173410c869004b987bf0beef

        - Exploit contract calls createDecreaseOrder
        createDecreaseOrder 0
        https://arbiscan.io/tx/0x20abfeff0206030986b05422080dc9e81dbb53a662fbc82461a47418decc49af

        - Keeper executes decrease order and initiates the loop
        executeDecreaseOrder 0
        https://arbiscan.io/tx/0x1f00da742318ad1807b6ea8283bfe22b4a8ab0bc98fe428fbfe443746a4a7353

        - Updater sets prices, executes order and creates a new decrease order
        setPricesWithBitsAndExecute / createDecreaseOrder 1
        https://arbiscan.io/tx/0x222cdae82a8d28e53a2bddfb34ae5d1d823c94c53f8a7abc179d47a2c994464e

        - Loop continues until the exploit contract executes final attack

    - Main Attack: 
    
        - Keeper executes decrease order 5
        executeDecreaseOrder 5 (MAIN EXPLOIT TX)
        https://arbiscan.io/tx/0x03182d3f0956a91c4e4c8f225bbc7975f9434fab042228c7acdc5ec9a32626ef

    - Fund Withdrawal:

        - Exploiter withdraws funds from the exploit contract
        https://arbiscan.io/tx/0x86486dceddcf581d43ab74e2ca381d4a8ee30a405ae17a81f4615986c0c75419


- **Attacker Addresses:**

    - Exploiter's EOA: [0xDF3340A436c27655bA62F8281565C9925C3a5221](https://arbiscan.io/address/0xdf3340a436c27655ba62f8281565c9925c3a5221)

    - Attacker's Smart Contract: [0x7d3bd50336f64b7a473c51f54e7f0bd6771cc355](https://arbiscan.io/address/0x7D3BD50336f64b7A473C51f54e7f0Bd6771cc355)

- **Attack Block:**: 355880237
- **Date:** July 9, 2025
- **Reproduce:** `forge test --match-contract Exploit_GMX -vvv --via-ir`

## Step-by-step Overview

## Detailed Description

```solidity
function _swapViaRouter(
    address positionManager,
    Rebalancer.PositionState memory position,
    bool zeroToOne,
    bytes memory swapData
) internal returns (uint256 balance0, uint256 balance1) {
    // Decode the swap data.
    (address router, uint256 amountIn, bytes memory data) = abi.decode(swapData, (address, uint256, bytes));

    // Approve token to swap.
    address tokenToSwap = zeroToOne ? position.token0 : position.token1;
    ERC20(tokenToSwap).safeApproveWithRetry(router, amountIn);

    // Execute arbitrary swap.
    (bool success, bytes memory result) = router.call(data);
    require(success, string(result));

    // Pool should still be balanced (within tolerance boundaries) after the swap.
    // Since the swap went potentially through the pool itself (but does not have to),
    // the sqrtPriceX96 might have moved and brought the pool out of balance.
    // By fetching the sqrtPriceX96, the transaction will revert in that case on the balance check.
    if (positionManager == address(UniswapV3Logic.POSITION_MANAGER)) {
        (position.sqrtPriceX96,,,,,,) = IUniswapV3Pool(position.pool).slot0();
    } else {
        // Logic holds for both Slipstream and staked Slipstream positions.
        (position.sqrtPriceX96,,,,,) = ICLPool(position.pool).slot0();
    }

    // Update the balances.
    balance0 = ERC20(position.token0).balanceOf(address(this));
    balance1 = ERC20(position.token1).balanceOf(address(this));
}
```

### Root Cause

### Attack Overview

## Possible mitigations


## Sources and references

- [Rekt]()
- [Tweet]()

---

REBALANCER.rebalance
ACCOUNT_1.flashAction