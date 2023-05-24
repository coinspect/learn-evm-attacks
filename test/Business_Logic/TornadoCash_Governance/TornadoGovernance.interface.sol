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
    function lockWithApproval(uint256 amount) external;
    function unlock(uint256 amount) external;
    function propose(address target, string memory description) external returns (uint256);
    function execute(uint256 proposalId) external payable;
    function lockedBalance(address from) external returns (uint256);
}
