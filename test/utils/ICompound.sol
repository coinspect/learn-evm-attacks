// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
interface ICompound {
    function borrow(uint256 borrowAmount) external;
    function repayBorrow(uint256 repayAmount) external;
    function redeem(uint256 redeemAmount) external;
    function mint(uint256 amount) external;
    function comptroller() external view returns(address);
}