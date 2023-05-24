// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {CheatCodes} from "./interfaces/00_CheatCodes.interface.sol";
import {IERC20} from "./interfaces/IERC20.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

contract TestHarness is Test {
    using Strings for uint256;
    using Strings for address;

    using stdStorage for StdStorage;

    CheatCodes cheat = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    StdStorage public stdStore;

    function writeTokenBalance(address who, address token, uint256 amt) internal {
        stdStore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }

    function anvil_mine_block() public {
        string[] memory instruction = new string[](2);
        instruction[0] = "ffi/anvil-custom";
        instruction[1] = "mine";
        vm.ffi(instruction);
    }

    function anvil_mine_blocks(uint256 amount) public {
        string[] memory instruction = new string[](3);
        instruction[0] = "ffi/anvil-custom";
        instruction[1] = "mine";
        instruction[2] = amount.toHexString(16);
        vm.ffi(instruction);
    }

    function anvil_mine_up_to(uint256 blockNumber) public {
        uint256 curBlock = block.number;
        require(blockNumber > curBlock, "Cant mine to a past block");
        uint256 blocksToMine = blockNumber - curBlock;
        anvil_mine_blocks(blocksToMine);
    }

    function anvil_mine_up_to(uint256 blockNumber, uint256 jumpIntervals) public {
        uint256 curBlock = block.number;
        uint256 amtToMine = (blockNumber - curBlock) / jumpIntervals;

        for (uint256 i = 0; i < amtToMine; i++) {
            anvil_mine_blocks(jumpIntervals);
            if (block.number >= blockNumber) {
                return;
            }
        }
    }

    function anvil_auto_impersonate() public {
        string[] memory instruction = new string[](2);
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
