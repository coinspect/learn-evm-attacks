// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IFastPriceFeed {
    // Only the updater can call this function
    function setPricesWithBitsAndExecute(
        uint256 _priceBits,
        uint256 _timestamp,
        uint256 _endIndexForIncreasePositions,
        uint256 _endIndexForDecreasePositions,
        uint256 _maxIncreasePositions,
        uint256 _maxDecreasePositions
    ) external;
}