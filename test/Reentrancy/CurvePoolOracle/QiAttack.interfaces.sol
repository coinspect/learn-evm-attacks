// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {IUniswapV2Router02} from "../../utils/IUniswapV2Router.sol";

interface IUnitroller {
    function enterMarkets(address[] memory cTokens) external payable returns (uint256[] memory);

    function exitMarket(address market) external;

    // Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
    function borrowCaps(address market) external view returns (uint256);

    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256);
}

interface IPriceFeed {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}

interface IVault is IERC20 {
    function deposit(uint256) external;

    function depositAll() external;

    function withdraw(uint256) external;

    function withdrawAll() external;

    function getPricePerFullShare() external view returns (uint256);

    function upgradeStrat() external;

    function balance() external view returns (uint256);

    function want() external view returns (IERC20);
}

interface ICERC20Delegator {
    function mint(uint256 mintAmount) external payable returns (uint256);

    function balanceOf(address _of) external view returns (uint256);

    function decimals() external view returns (uint16);

    function borrow(uint256 borrowAmount) external payable returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);

    function accrueInterest() external;

    function approve(address spender, uint256 amt) external;

    function redeemUnderlying(uint256 redeemAmount) external payable returns (uint256);

    function underlying() external returns (address);

    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral)
        external
        returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface ICurvePool {
    function add_liquidity(uint256[2] memory amounts, uint256 min_min_amount, bool use_eth)
        external
        payable
        returns (uint256);

    function remove_liquidity(uint256 amount, uint256[2] calldata min_amounts, bool use_eth) external payable;

    function token() external pure returns (address);

    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy, bool use_eth)
        external
        payable
        returns (uint256);
}

interface IAaveFlashloan {
    function flashLoan(
        address arg0,
        address[] memory arg1,
        uint256[] memory arg2,
        uint256[] memory arg3,
        address arg4,
        bytes memory arg5,
        uint16 arg6
    ) external;
}

// =============================== HELPER FUNCTIONS ===============================

// Gets the price of Curve LP tokens (Beefy's underlying) according to the
// Compound price's feed
function get_lp_token_price_for_compound() view returns (uint256) {
    return IPriceFeed(0x71585E806402473Ff25eda3e2C3C17168767858a).getUnderlyingPrice(0x570Bc2b7Ad1399237185A27e66AEA9CfFF5F3dB8); // STMATIC_MATIC_DELEGATOR
}
