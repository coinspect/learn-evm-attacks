// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IAccount {
    function setAssetManager(address assetManager, bool value) external;

    function deposit(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts
    ) external;

    function ACCOUNT_VERSION() external view returns (uint256);

    function generateAssetData()
        external
        view
        returns (
            address[] memory assetAddresses,
            uint256[] memory assetIds,
            uint256[] memory assetAmounts
        );

    function withdraw(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts
    ) external;
}
