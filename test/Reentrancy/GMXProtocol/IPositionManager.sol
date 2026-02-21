// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPositionManager {
    // This functions can only be called by the keeper
    function executeDecreaseOrder(address _account, uint256 _orderIndex, address payable _feeReceiver) external;
    function executeIncreaseOrder(address _account, uint256 _orderIndex, address payable _feeReceiver) external;
}