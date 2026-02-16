// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ICurve {
    function get_virtual_price() external view returns (uint256);

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount)
        external
        payable
        returns (uint256);

    function remove_liquidity(uint256 lp, uint256[2] calldata min_amounts)
        external
        returns (uint256[2] memory);

    function remove_liquidity_one_coin(uint256 lp, int128 i, uint256 min_amount) external returns (uint256);

    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external;
}
