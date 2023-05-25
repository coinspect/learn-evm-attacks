// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IReinitializableContractFactory {
    function deployMaliciousProposal() external returns (bool);
}

interface IMaliciousSelfDestruct {
    function emergencyStop() external;
}

interface IProposal {
    function executeProposal() external;
}

interface IRelayerRegistry {
    function getRelayerBalance(address relayer) external returns (uint256);
    function isRelayer(address relayer) external returns (bool);
    function setMinStakeAmount(uint256 minAmount) external;
    function nullifyBalance(address relayer) external;
}

interface IStakingRewards {
    function withdrawTorn(uint256 amount) external;
}

interface ITornadoGovernance {
    enum ProposalState {
        Pending,
        Active,
        Defeated,
        Timelocked,
        AwaitingExecution,
        Executed,
        Expired
    }

    struct Proposal {
        // Creator of the proposal
        address proposer;
        // target addresses for the call to be made
        address target;
        // The block at which voting begins
        uint256 startTime;
        // The block at which voting ends: votes must be cast prior to this block
        uint256 endTime;
        // Current number of votes in favor of this proposal
        uint256 forVotes;
        // Current number of votes in opposition to this proposal
        uint256 againstVotes;
        // Flag marking whether the proposal has been executed
        bool executed;
        // Flag marking whether the proposal voting time has been extended
        // Voting time can be extended once, if the proposal outcome has changed during CLOSING_PERIOD
        bool extended;
        // Receipts of ballots for the entire set of voters
        mapping(address => Receipt) receipts;
    }

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        // Whether or not a vote has been cast
        bool hasVoted;
        // Whether or not the voter supports the proposal
        bool support;
        // The number of votes the voter had, which were cast
        uint256 votes;
    }

    function lockWithApproval(uint256 amount) external;
    function unlock(uint256 amount) external;
    function propose(address target, string memory description) external returns (uint256);
    function execute(uint256 proposalId) external payable;
    function lockedBalance(address from) external returns (uint256);
    function state(uint256 proposalId) external view returns (ProposalState);
    function castVote(uint256 proposalId, bool support) external;
}
