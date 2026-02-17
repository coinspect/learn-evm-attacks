pragma solidity ^0.8.20;

import {UD60x18, convert, ud, add, mul, pow, sub, div, unwrap} from "@prb-math/UD60x18.sol";

library SwapMath {
    /// @notice minimum 1-t to not div by 0
    uint256 internal constant MINIMUM_ELAPSED = 1;

    /// @notice amountOut = reserveOut - (k - (reserveIn + amountIn)^(1-t))^1/(1-t)
    /// the fee here is taken from the input token and generally doesn't need to be exposed to the user
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 _1MinT,
        uint256 baseFee
    ) internal pure returns (uint256 amountOut, uint256 fee) {
        (UD60x18 amountOutRaw, UD60x18 feeRaw) =
            _getAmountOut(ud(amountIn), ud(reserveIn), ud(reserveOut), ud(_1MinT), ud(baseFee));

        amountOut = unwrap(amountOutRaw);
        fee = unwrap(feeRaw);
    }

    function _getAmountOut(
        UD60x18 amountIn,
        UD60x18 reserveIn,
        UD60x18 reserveOut,
        UD60x18 _1MinT,
        UD60x18 baseFee
    ) internal pure returns (UD60x18 amountOut, UD60x18 fee) {
        // Calculate fee factor = baseFee x t in percentage, we complement _1MinT to get t
        // the end result should be total fee that we must take out
        UD60x18 feeFactor = mul(baseFee, sub(convert(1), _1MinT));
        fee = _calculatePercentage(amountIn, feeFactor);

        // Calculate amountIn after fee = amountIn * feeFactor
        amountIn = sub(amountIn, fee);

        UD60x18 reserveInExp = pow(reserveIn, _1MinT);
        UD60x18 reserveOutExp = pow(reserveOut, _1MinT);

        UD60x18 k = add(reserveInExp, reserveOutExp);

        // Calculate q = (k - (reserveIn + amountIn)^(1-t))^1/(1-t)
        UD60x18 q = add(reserveIn, amountIn);
        q = pow(q, _1MinT);
        q = pow(sub(k, q), div(convert(1), _1MinT));

        // Calculate amountOut = reserveOut - q
        amountOut = sub(reserveOut, q);
    }

    /// @notice amountIn = (k - (reserveOut - amountOut)^(1-t))^1/(1-t) - reserveIn
    /// the fee here is taken from the input token is already included in amountIn
    /// the fee is generally doesn't need to be exposed to the user since internally it's only used for
    /// splitting fees between LPs and the protocol
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 _1MinT,
        uint256 baseFee
    ) internal pure returns (uint256 amountIn, uint256 fee) {
        (UD60x18 amountInRaw, UD60x18 feeRaw) =
            _getAmountIn(ud(amountOut), ud(reserveIn), ud(reserveOut), ud(_1MinT), ud(baseFee));

        amountIn = unwrap(amountInRaw);
        fee = unwrap(feeRaw);
    }

    function _getAmountIn(
        UD60x18 amountOut,
        UD60x18 reserveIn,
        UD60x18 reserveOut,
        UD60x18 _1MinT,
        UD60x18 baseFee
    ) internal pure returns (UD60x18 amountIn, UD60x18 fee) {
        UD60x18 reserveInExp = pow(reserveIn, _1MinT);

        UD60x18 reserveOutExp = pow(reserveOut, _1MinT);

        UD60x18 k = reserveInExp.add(reserveOutExp);

        // Calculate q = (reserveOut - amountOut)^(1-t))^1/(1-t)
        UD60x18 q = pow(sub(reserveOut, amountOut), _1MinT);
        q = pow(sub(k, q), div(convert(1), _1MinT));

        // Calculate amountIn = q - reserveIn
        amountIn = sub(q, reserveIn);

        // normalize fee factor to 0-1
        UD60x18 feeFactor = div(mul(baseFee, sub(convert(1), _1MinT)), convert(100));
        feeFactor = sub(convert(1), feeFactor);

        UD60x18 adjustedAmountIn = div(amountIn, feeFactor);

        fee = sub(adjustedAmountIn, amountIn);

        assert(add(amountIn, fee) == adjustedAmountIn);

        amountIn = adjustedAmountIn;
    }

    function getNormalizedTimeToMaturity(uint256 startTime, uint256 maturityTime, uint256 currentTime)
        internal
        pure
        returns (uint256)
    {
        return unwrap(_getNormalizedTimeToMaturity(ud(startTime), ud(maturityTime), ud(currentTime)));
    }

    function _getNormalizedTimeToMaturity(UD60x18 startTime, UD60x18 maturityTime, UD60x18 currentTime)
        internal
        pure
        returns (UD60x18 t)
    {
        UD60x18 elapsedTime = currentTime.sub(startTime);
        elapsedTime = elapsedTime == ud(0) ? ud(MINIMUM_ELAPSED) : elapsedTime;
        UD60x18 totalDuration = maturityTime.sub(startTime);

        // we return 0 in case it's past maturity time
        if (elapsedTime >= totalDuration) {
            return convert(0);
        }

        // Return a normalized time between 0 and 1 (as a percentage in 18 decimals)
        t = sub(convert(1), div(elapsedTime, totalDuration));
    }

    /// @notice calculate 1 - t
    function oneMinusT(uint256 startTime, uint256 maturityTime, uint256 currentTime)
        internal
        pure
        returns (uint256)
    {
        return _oneMinusT(startTime, maturityTime, currentTime);
    }

    function _oneMinusT(uint256 startTime, uint256 maturityTime, uint256 currentTime)
        internal
        pure
        returns (uint256)
    {
        return unwrap(
            sub(convert(1), _getNormalizedTimeToMaturity(ud(startTime), ud(maturityTime), ud(currentTime)))
        );
    }

    /// @notice feePercentage =  baseFee x t. where t is normalized time
    function getFeePercentage(uint256 baseFee, uint256 startTime, uint256 maturityTime, uint256 currentTime)
        internal
        pure
        returns (uint256)
    {
        UD60x18 t = _getNormalizedTimeToMaturity(ud(startTime), ud(maturityTime), ud(currentTime));
        return unwrap(mul(ud(baseFee), t));
    }

    /// @notice calculate percentage of an amount = amount * percentage / 100
    function _calculatePercentage(UD60x18 amount, UD60x18 percentage) internal pure returns (UD60x18 result) {
        result = div(mul(amount, percentage), convert(100));
    }

    function calculatePercentage(uint256 amount, uint256 percentage) internal pure returns (uint256) {
        return unwrap(_calculatePercentage(ud(amount), ud(percentage)));
    }

    /// @notice calculate fee = amount * (baseFee x t) / 100
    function getFee(
        uint256 amount,
        uint256 baseFee,
        uint256 startTime,
        uint256 maturityTime,
        uint256 currentTime
    ) internal pure returns (uint256) {
        uint256 feePercentage = getFeePercentage(baseFee, startTime, maturityTime, currentTime);
        return unwrap(_calculatePercentage(ud(feePercentage), ud(amount)));
    }

    /// @notice calculate k = x^(1-t) + y^(1-t)
    function getInvariant(
        uint256 reserve0,
        uint256 reserve1,
        uint256 startTime,
        uint256 maturityTime,
        uint256 currentTime
    ) internal pure returns (uint256 k) {
        uint256 t = oneMinusT(startTime, maturityTime, currentTime);

        // Calculate x^(1-t) and y^(1-t) (x and y are reserveRA and reserveCT)
        UD60x18 xTerm = pow(ud(reserve0), ud(t));
        UD60x18 yTerm = pow(ud(reserve1), ud(t));

        // Invariant k is x^(1-t) + y^(1-t)
        k = unwrap(add(xTerm, yTerm));
    }
}
