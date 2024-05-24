// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

contract Exploit_Curio is TestHarness, TokenBalanceTracker {
    // Instances of tokens involved

    // Instances of relevant contracts

    function setUp() external {
        // Create a fork right before the attack started

        // Setup attacker account (this contract)

        // Initialize labels and token tracker
        _labelAccounts();
        _tokenTrackerSetup();
    }

    function _labelAccounts() internal {
        cheat.label(address(this), "Attacker");
    }

    function _tokenTrackerSetup() internal {
        // Add relevant tokens to tracker

        // Initialize user's state
        updateBalanceTracker(address(this));
    }
}
