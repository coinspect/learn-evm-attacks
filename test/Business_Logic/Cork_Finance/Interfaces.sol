// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "../../interfaces/IERC20.sol";

interface ICorkHook {
    function addLiquidity(
        address ra,
        address ct,
        uint256 raAmount,
        uint256 ctAmount,
        uint256 amountRamin,
        uint256 amountCtmin,
        uint256 deadline
    ) external returns (uint256 amountRa, uint256 amountCt, uint256 mintedLp);

    function getLiquidityToken(address ra, address ct) external view returns (address);
}

interface IMyToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface IPSMProxy {
    error NotInitialized();
    error PSMDepositPaused();

    struct BuyAprroxParams {
        /// @dev the maximum amount of iterations to find the optimal amount of DS to swap, 256 is a good
        /// number
        uint256 maxApproxIter;
        /// @dev the maximum amount of iterations to find the optimal RA borrow amount(needed because of the
        /// fee, if any)
        uint256 maxFeeIter;
        /// @dev the amount that will be used to subtract borrowed amount to find the optimal amount for
        /// borrowing RA
        /// the lower the value, the more accurate the approximation will be but will be more expensive
        /// when in doubt use 0.01 ether or 1e16
        uint256 feeIntervalAdjustment;
        /// @dev the threshold tolerance that's used to find the optimal DS amount
        /// when in doubt use 1e9
        uint256 epsilon;
        /// @dev the threshold tolerance that's used to find the optimal RA amount to borrow, the smaller, the
        /// more accurate but more gas intensive it will be
        uint256 feeEpsilon;
        /// @dev the percentage buffer that's used to find the optimal DS amount. needed due to the inherent
        /// nature
        /// of the math that has some imprecision, this will be used to subtract the original amount, to
        /// offset the precision
        /// when in doubt use 0.01%(1e16) if you're trading above 0.0001 RA. Below that use 1-10%(1e17-1e18)
        uint256 precisionBufferPercentage;
    }

    /// @notice offchain guess for RA AMM borrowing used in swapping RA for DS.
    /// if empty, the router will try and calculate the optimal amount of RA to borrow
    /// using this will greatly reduce the gas cost.
    /// will be the default way to swap RA for DS
    struct OffchainGuess {
        uint256 initialBorrowAmount;
        uint256 afterSoldBorrowAmount;
    }

    struct SwapRaForDsReturn {
        uint256 amountOut;
        uint256 ctRefunded;
        /// @dev the amount of RA that needs to be borrowed on first iteration, this amount + user supplied /
        /// 2 of DS
        /// will be sold from the reserve unless it doesn't met the minimum amount, the DS reserve is empty,
        /// or the DS reserve sale is disabled. in such cases, this will be the final amount of RA that's
        /// borrowed
        /// and the "afterSoldBorrow" will be 0.
        /// if the swap is fully fullfilled by the rollover sale, both initialBorrow and afterSoldBorrow will
        /// be 0
        uint256 initialBorrow;
        /// @dev the final amount of RA that's borrowed after selling DS reserve
        uint256 afterSoldBorrow;
        uint256 fee;
    }

    function approve(address spender, uint256 amount) external returns (bool);
    function swapRaforDs(
        bytes32 reserveId,
        uint256 dsId,
        uint256 amount,
        uint256 amountOutMin,
        BuyAprroxParams memory params,
        OffchainGuess memory offchainGuess
    ) external returns (SwapRaForDsReturn memory result);

    function depositPsm(bytes32 id, uint256 amount)
        external
        returns (uint256 received, uint256 exchangeRate);
}

interface IExchangeRateProvider {
    function rate(bytes32 id) external view returns (uint256);
}
