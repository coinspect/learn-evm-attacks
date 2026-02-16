// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// From OrderLib library
// File @1inch/limit-order-protocol/contracts/OrderLib.sol@v0.3.0-prerelease
struct Order {
    uint256 salt;
    address makerAsset;
    address takerAsset;
    address maker;
    address receiver;
    address allowedSender; // equals to Zero address on public orders
    uint256 makingAmount;
    uint256 takingAmount;
    uint256 offsets;
    // bytes makerAssetData;
    // bytes takerAssetData;
    // bytes getMakingAmount; // this.staticcall(abi.encodePacked(bytes, swapTakerAmount)) =>
    // (swapMakerAmount)
    // bytes getTakingAmount; // this.staticcall(abi.encodePacked(bytes, swapMakerAmount)) =>
    // (swapTakerAmount)
    // bytes predicate;       // this.staticcall(bytes) => (bool)
    // bytes permit;          // On first fill: permit.1.call(abi.encodePacked(permit.selector, permit.2))
    // bytes preInteraction;
    // bytes postInteraction;
    bytes interactions; // concat(makerAssetData, takerAssetData, getMakingAmount, getTakingAmount, predicate,
    // permit, preIntercation, postInteraction)
}

interface IUSDT {
    function approve(address _spender, uint256 _value) external;
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address _to, uint256 _value) external;
    function allowance(address owner, address spender) external returns (uint256);
}

interface ISettlement {
    function settleOrders(bytes calldata order) external;
}
