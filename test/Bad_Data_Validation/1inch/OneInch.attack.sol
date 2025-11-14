// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {IUniswapV2Router02} from "../../utils/IUniswapV2Router.sol";


// Victim addresses:
// https://etherscan.io/address/0xb02f39e382c90160eb816de5e0e428ac771d77b5 (TrustedVolumes)
// https://etherscan.io/address/0xa88800cd213da5ae406ce248380802bd53b47647 (1inch Settlement V1)

interface IUSDT {
    function approve(address _spender, uint256 _value) external;
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address _to, uint256 _value) external;
    function allowance(address owner, address spender) external returns (uint);
}
contract Exploit_OneInch is TestHarness, TokenBalanceTracker{
    
    address private constant ATTACKER = 0xA7264a43A57Ca17012148c46AdBc15a5F951766e;
    uint256 INITIAL_BALANCE = 0.096781739662413385 ether;
    uint256 INITAL_USDT_AMOUNT = 1e6;
    uint256 INITAL_WETH_AMOUNT = 0.001 ether;
    uint256 INTIAL_SWAP_AMOUNT= 0.0005 ether;


    IUSDT internal constant USDT = IUSDT(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IWETH9 private constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // DEX
    address internal UNISWAP_V2_ROUTER02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    // 1. tx approve AggregationRouterV5
    address private constant AggregationRouterV5 = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    IUniswapV2Router02 uniswap;
    address[] public path;
    exploit attackerContract;

    function setUp() public {
        // Fork the chain one block before the exploit occurred
        attackerContract = new exploit();   
        cheat.createSelectFork(vm.envString("RPC_URL"),21977371);
        uniswap = IUniswapV2Router02(UNISWAP_V2_ROUTER02);

        deal(address(this), 0);
        // Set Initial balance 
        deal(address(WETH),address(attackerContract), INITAL_WETH_AMOUNT);
        vm.startPrank(ATTACKER);
        path = [address(WETH), address(USDT)];
        uniswap.swapETHForExactTokens{value:INTIAL_SWAP_AMOUNT}(INITAL_USDT_AMOUNT,path, address(attackerContract),block.timestamp);
         deal(address(attackerContract),INITIAL_BALANCE);

        // Set up token balance tracking for logging.
        addTokenToTracker(address(USDC));
        addTokenToTracker(address(USDT));
        addTokenToTracker(address(WETH));
    }

    function test_attack() public {
        console.log("------- INITIAL BALANCES -------");
        logBalancesWithLabel("Attacker", ATTACKER);
        logBalancesWithLabel("ExploitMock", address(attackerContract));

        console.log("------- 2. tx SWAP -------");

        
    }
}


contract exploit {

}

