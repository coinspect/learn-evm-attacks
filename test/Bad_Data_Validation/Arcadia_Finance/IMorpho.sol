// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IMorpho {
    function flashLoan(
        address token,
        uint256 assets,
        bytes calldata data
    ) external;
}
