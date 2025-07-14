// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IVault {
    struct VaultParameters {
        address debtToken;
        address collateralToken;
        int8 leverageTier;
    }

    /** Collateral owned by the apes and LPers in a vault
     */
    struct Reserves {
        uint144 reserveApes;
        uint144 reserveLPers;
        int64 tickPriceX42;
    }

    /** Data needed for recoverying the amount of collateral owned by the apes and LPers in a vault
     */
    struct VaultState {
        uint144 reserve; // reserve =  reserveApes + reserveLPers
        /** Price at the border of the power and saturation zone.
            Q21.42 - Fixed point number with 42 bits of precision after the comma.
            type(int64).max and type(int64).min are used to represent +∞ and -∞ respectively.
         */
        int64 tickPriceSatX42; // Saturation price in Q21.42 fixed point
        uint48 vaultId; // Allows the creation of approximately 281 trillion vaults
    }

    /** The sum of all amounts in Fees are equal to the amounts deposited by the user (in the case of a mint)
        or taken out by the user (in the case of a burn).
        collateralInOrWithdrawn: Amount of collateral deposited by the user (in the case of a mint) or taken out by the user (in the case of a burn).
        collateralFeeToStakers: Amount of collateral paid to the stakers.
        collateralFeeToLPers: Amount of collateral paid to the gentlemen.
        collateralFeeToProtocol: Amount of collateral paid to the protocol.
     */
    struct Fees {
        uint144 collateralInOrWithdrawn;
        uint144 collateralFeeToStakers;
        uint144 collateralFeeToLPers; // Sometimes all LPers and sometimes only protocol owned liquidity
    }

    /**
     * @notice Initialization is always necessary because we must deploy the APE contract for each vault,
     * and possibly initialize the Oracle.
     */
    function initialize(VaultParameters memory vaultParams) external;

    /**
     * @notice Function for minting APE or TEA, the protocol's synthetic tokens.\n
     * You can mint by depositing collateral token or debt token dependening by setting collateralToDepositMin to 0 or not, respectively.\n
     * You have the option to mint with vanilla ETH when the token is WETH by simply sending ETH with the call. In this case, amountToDeposit is ignored.
     * @dev When minting APE, the user will give away a portion of his deposited collateral to the LPers.\n
     * When minting TEA, the user will give away a portion of his deposited collateral to protocol owned liquidity.
     * @param isAPE If true, mint APE. If false, mint TEA
     * @param vaultParams The 3 parameters identifying a vault: collateral token, debt token, and leverage tier.
     * @param amountToDeposit Collateral amount to deposit if collateralToDepositMin == 0, debt token to deposit if collateralToDepositMin > 0
     * @param collateralToDepositMin Ignored when minting with collateral token, otherwise it specifies the minimum amount of collateral to receive from Uniswap when swapping the debt token.
     * @return amount of tokens TEA/APE obtained
     */
    function mint(
        bool isAPE,
        VaultParameters memory vaultParams,
        uint256 amountToDeposit, // Collateral amount to deposit if collateralToDepositMin == 0, debt token to deposit if collateralToDepositMin > 0
        uint144 collateralToDepositMin
    ) external payable returns (uint256 amount);

    /**
     * @dev This callback function is required by Uniswap pools when making a swap.\n
     * This function is exectuted when the user decides to mint TEA or APE with debt token.\n
     * This function is in charge of sending the debt token to the uniswwap pool.\n
     * It will revert if any external actor that is not a Uniswap pool calls this function.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}