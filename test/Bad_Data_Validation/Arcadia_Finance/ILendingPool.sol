// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILendingPool{
    function repay(uint256 amount, address account) external;
    function maxWithdraw(address owner) external view returns (uint256);
}