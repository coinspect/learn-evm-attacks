pragma solidity ^0.8.17;
import {TestHarness} from "../../TestHarness.sol";
import "forge-std/Test.sol";
import {UintToString} from "./StringsLib.sol";

contract TestStringsToUint is TestHarness {
    using UintToString for uint256;
    function testToStringWithDecimals() external {
        uint256 test0 = 0;
        uint256 test1Wei = 1;
        uint256 test10Wei = 10;
        uint256 test1EtherAnd10Wei = 1000000000000000010;
        uint256 test1Ether = 1000000000000000000;
        assertEq(keccak256('0'), keccak256(abi.encodePacked(test0.toStringWithDecimals(18))));
        assertEq(keccak256('0.000000000000000001'), keccak256(abi.encodePacked(test1Wei.toStringWithDecimals(18))));
        assertEq(keccak256('0.000000000000000010'), keccak256(abi.encodePacked(test10Wei.toStringWithDecimals(18))));
        assertEq(keccak256('1.000000000000000010'), keccak256(abi.encodePacked(test1EtherAnd10Wei.toStringWithDecimals(18))));
        assertEq(keccak256('1'), keccak256(abi.encodePacked(test1Ether.toStringWithDecimals(18))));
    }
}
