// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.17;

// The code for this contract can be found at: https://etherscan.io/address/0x0000000000ffe8b47b3e2130213b802212439497#code
interface IImmutableCreate2Factory {
    function safeCreate2(
        bytes32 salt,
        bytes calldata initializationCode
    ) external payable returns (address deploymentAddress);

    function findCreate2Address(
        bytes32 salt,
        bytes calldata initCode
    ) external view returns (address deploymentAddress);
}