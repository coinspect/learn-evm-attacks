// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./MurkyBase.sol";

/// @notice Nascent, simple, kinda efficient (and improving!) Merkle proof generator and verifier
/// @author dmfxyz
/// @dev Note Generic Merkle Tree
contract MerkleTree is MurkyBase {

    /********************
    * HASHING FUNCTION *
    ********************/

    /// ascending sort and concat prior to hashing
    function hashLeafPairs(bytes32 left, bytes32 right) public pure override returns (bytes32 _hash) {
       assembly {
           switch lt(left, right)
           case 0 {
               mstore(0x0, right)
               mstore(0x20, left)
           }
           default {
               mstore(0x0, left)
               mstore(0x20, right)
           }
           _hash := keccak256(0x0, 0x40)
       }
    }
}