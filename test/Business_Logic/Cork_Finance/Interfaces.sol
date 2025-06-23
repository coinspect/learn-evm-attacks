// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "../../interfaces/IERC20.sol";

interface ICorkConfig {}

interface IUniV4PoolManager {}

interface ICorkHook {
    error OnlyConfigAllowed();

    struct MarketSnapshot {
        address ra;
        address ct;
        uint256 reserveRa;
        uint256 reserveCt;
        uint256 oneMinusT;
        uint256 baseFee;
        address liquidityToken;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 treasuryFeePercentage;
    }

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
    function getReserves(address ra, address ct) external view returns (uint256, uint256);
    function swap(address ra, address ct, uint256 amountRaOut, uint256 amountCtOut, bytes calldata data)
        external
        returns (uint256 amountIn);

    function updateBaseFeePercentage(address ra, address ct, uint256 baseFeePercentage) external;
    function updateTreasurySplitPercentage(address ra, address ct, uint256 treasurySplit) external;
    function getFee(address ra, address ct)
        external
        view
        returns (uint256 baseFeePercentage, uint256 actualFeePercentage);

    function getMarketSnapshot(address ra, address ct) external view returns (MarketSnapshot memory);
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

    function getDeployedSwapAssets(
        address ra,
        address pa,
        uint256 initialArp,
        uint256 expiryInterval,
        address exchangeRateProvider,
        uint8 page,
        uint8 limit
    ) external view returns (address[] memory ct, address[] memory ds);

    // Used by the deployer
    function issueNewDs(
        bytes32 id,
        uint256 decayDiscountRateInDays, // protocol-level config
        // won't have effect on first issuance
        uint256 rolloverPeriodInblocks, // protocol-level config
        uint256 ammLiquidationDeadline
    ) external;

    function lastDsId(bytes32 id) external returns (uint256 dsId);
    function underlyingAsset(bytes32 id) external view returns (address ra, address pa);
    function swapAsset(bytes32 id, uint256 dsId) external view returns (address ct, address ds);
}

interface IExchangeRateProvider {
    function rate(bytes32 id) external view returns (uint256);
}
