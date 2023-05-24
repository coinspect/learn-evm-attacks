// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {CheatCodes} from "./interfaces/00_CheatCodes.interface.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract TestHarness is Test {
    using stdStorage for StdStorage;

    CheatCodes cheat = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    StdStorage public stdStore;

    function writeTokenBalance(address who, address token, uint256 amt) internal {
        stdStore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }

    function mine_anvil_block() public {
        string[] memory instruction = new string[](2);
        instruction[0] = "ffi/anvil-custom";
        instruction[1] = "mine";
        vm.ffi(instruction);
    }

    function anvil_impersonate_whale() public {
        string[] memory instruction = new string[](2);
        instruction[0] = "ffi/anvil-custom";
        instruction[1] = "impersonate-whale";
        vm.ffi(instruction);

        instruction[0] = "ffi/anvil-custom";
        instruction[1] = "auto-impersonation";
        vm.ffi(instruction);
    }

    function anvil_stop_impersonation() public {
        string[] memory instruction = new string[](2);
        instruction[0] = "ffi/anvil-custom";
        instruction[1] = "stop-impersonation";
        vm.ffi(instruction);
    }
}
