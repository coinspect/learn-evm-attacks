// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
interface ICurve {
  function get_virtual_price() external view returns (uint);

  function add_liquidity(uint[2] calldata amounts, uint min_mint_amount)
    external
    payable
    returns (uint);

  function remove_liquidity(uint lp, uint[2] calldata min_amounts)
    external
    returns (uint[2] memory);

  function remove_liquidity_one_coin(
    uint lp,
    int128 i,
    uint min_amount
  ) external returns (uint);

  function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external;
}