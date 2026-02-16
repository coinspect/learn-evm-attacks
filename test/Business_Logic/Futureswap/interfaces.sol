// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Aave V3 Pool interface for flashloan
interface IPool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

// Interface required to receive flashloan
interface IFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

// Futureswap interface
interface IFutureswap {
    function updateFunding() external;
    function longPosition() external view returns (int256, int256);
    function changePosition(int256 deltaAsset, int256 deltaStable, int256 stableBound)
        external
        returns (int256, int256, int256, int256, int256, int256);
}
