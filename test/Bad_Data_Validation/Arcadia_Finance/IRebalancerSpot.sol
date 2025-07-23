// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRebalancerSpot {
    error InitiatorNotValid();
    error InsufficientLiquidity();
    error InvalidValue();
    error NotAnAccount();
    error OnlyAccount();
    error OnlyAccountOwner();
    error OnlyPool();
    error OnlyPositionManager();
    error Reentered();
    error UnbalancedPool();

    function setAccountInfo(address account_, address initiator, address hook) external;

    function setInitiatorInfo(uint256 tolerance, uint256 fee, uint256 minLiquidityRatio) external;

    function rebalance(
        address account_,
        address positionManager,
        uint256 oldId,
        int24 tickLower,
        int24 tickUpper,
        bytes calldata swapData
    ) external;
}