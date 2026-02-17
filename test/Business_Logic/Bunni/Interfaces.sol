// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IUniswapV3Pool {
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

interface IUniswapV3FlashCallback {
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external;
}

interface IBunniHub {
    struct WithdrawParams {
        PoolKey poolKey;
        address recipient;
        uint256 shares;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
        bool useQueuedWithdrawal;
    }

    function withdraw(WithdrawParams calldata params) external returns (uint256 amount0, uint256 amount1);
}
