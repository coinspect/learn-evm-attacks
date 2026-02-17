// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPancakeRouter01 {
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
