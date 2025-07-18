// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IGlpManager {
    function getGlobalShortAveragePrice(
        address _token
    ) external view returns (uint256);

    function getAum(bool maximise) external view returns (uint256);
}
