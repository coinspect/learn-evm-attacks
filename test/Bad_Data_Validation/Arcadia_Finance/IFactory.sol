// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IFactory {
    function createAccount(
        uint32 salt,
        uint256 accountVersion,
        address creditor
    ) external returns (address account);
}
