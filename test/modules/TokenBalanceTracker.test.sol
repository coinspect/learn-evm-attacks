pragma solidity ^0.8.17;
import {TokenBalanceTracker} from './TokenBalanceTracker.sol';
import {TestHarness} from "../TestHarness.sol";
import "forge-std/Test.sol";
interface IERC20Local {
    function name() external view returns(string memory);
    function decimals() external view returns(uint8);
    function balanceOf(address account) external view returns (uint256);
}

contract TestTokenBalanceTracker is TestHarness, TokenBalanceTracker {
    address user = address(0x42);

    function testToStringWithDecimals() external {
        assertEq(keccak256('0'), keccak256(abi.encodePacked(toStringWithDecimals(0,18))));
        assertEq(keccak256('0.000000000000000001'), keccak256(abi.encodePacked(toStringWithDecimals(1,18))));
        assertEq(keccak256('0.000000000000000010'), keccak256(abi.encodePacked(toStringWithDecimals(10,18))));
        assertEq(keccak256('1.000000000000000010'), keccak256(abi.encodePacked(toStringWithDecimals(1000000000000000010,18))));
        assertEq(keccak256('1'), keccak256(abi.encodePacked(toStringWithDecimals(1000000000000000000,18))));
    }
}
