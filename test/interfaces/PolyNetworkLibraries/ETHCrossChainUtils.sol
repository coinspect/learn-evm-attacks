pragma solidity ^0.8.0;

import "./ZeroCopySource.sol";
import "./ZeroCopySink.sol";
import "./Utils.sol";

library ECCUtils {
    struct Header {
        uint32 version;
        uint64 chainId;
        uint32 timestamp;
        uint32 height;
        uint64 consensusData;
        bytes32 prevBlockHash;
        bytes32 transactionsRoot;
        bytes32 crossStatesRoot;
        bytes32 blockRoot;
        bytes consensusPayload;
        bytes20 nextBookkeeper;
        bytes padding;
    }

    struct ToMerkleValue {
        bytes txHash; // cross chain txhash
        uint64 fromChainID;
        TxParam makeTxParam;
    }

    struct TxParam {
        bytes txHash; //  source chain txhash
        bytes crossChainId;
        bytes fromContract;
        uint64 toChainId;
        bytes toContract;
        bytes method;
        bytes args;
    }

    uint256 constant POLYCHAIN_PUBKEY_LEN = 67;
    uint256 constant POLYCHAIN_SIGNATURE_LEN = 65;

    /* @notice                  Verify Poly chain transaction whether exist or not
    *  @param _auditPath        Poly chain merkle proof
    *  @param _root             Poly chain root
    *  @return                  The verified value included in _auditPath
    */
    function merkleProve(bytes memory _auditPath, bytes32 _root) internal pure returns (bytes memory) {
        uint256 off = 0;
        bytes memory value;
        (value, off) = ZeroCopySource.NextVarBytes(_auditPath, off);

        bytes32 hash = Utils.hashLeaf(value);
        uint256 size = (_auditPath.length - off) / 33;
        bytes32 nodeHash;
        bytes1 pos;
        for (uint256 i = 0; i < size; i++) {
            (pos, off) = ZeroCopySource.NextByte(_auditPath, off);
            (nodeHash, off) = ZeroCopySource.NextHash(_auditPath, off);
            if (pos == 0x00) {
                hash = Utils.hashChildren(nodeHash, hash);
            } else if (pos == 0x01) {
                hash = Utils.hashChildren(hash, nodeHash);
            } else {
                revert("merkleProve, NextByte for position info failed");
            }
        }
        require(hash == _root, "merkleProve, expect root is not equal actual root");
        return value;
    }

    /* @notice              calculate next book keeper according to public key list
    *  @param _keyLen       consensus node number
    *  @param _m            minimum signature number
    *  @param _pubKeyList   consensus node public key list
    *  @return              two element: next book keeper, consensus node signer addresses
    */
    function _getBookKeeper(uint256 _keyLen, uint256 _m, bytes memory _pubKeyList)
        internal
        pure
        returns (bytes20, address[] memory)
    {
        bytes memory buff;
        buff = ZeroCopySink.WriteUint16(uint16(_keyLen));
        address[] memory keepers = new address[](_keyLen);
        bytes32 hash;
        bytes memory publicKey;
        for (uint256 i = 0; i < _keyLen; i++) {
            publicKey = Utils.slice(_pubKeyList, i * POLYCHAIN_PUBKEY_LEN, POLYCHAIN_PUBKEY_LEN);
            buff = abi.encodePacked(buff, ZeroCopySink.WriteVarBytes(Utils.compressMCPubKey(publicKey)));
            hash = keccak256(Utils.slice(publicKey, 3, 64));
            keepers[i] = address(uint160(uint256(hash)));
        }

        buff = abi.encodePacked(buff, ZeroCopySink.WriteUint16(uint16(_m)));
        bytes20 nextBookKeeper = ripemd160(abi.encodePacked(sha256(buff)));
        return (nextBookKeeper, keepers);
    }

    /* @notice              Verify public key derived from Poly chain
    *  @param _pubKeyList   serialized consensus node public key list
    *  @param _sigList      consensus node signature list
    *  @return              return two element: next book keeper, consensus node signer addresses
    */
    function verifyPubkey(bytes memory _pubKeyList) internal pure returns (bytes20, address[] memory) {
        require(_pubKeyList.length % POLYCHAIN_PUBKEY_LEN == 0, "_pubKeyList length illegal!");
        uint256 n = _pubKeyList.length / POLYCHAIN_PUBKEY_LEN;
        require(n >= 1, "too short _pubKeyList!");
        return _getBookKeeper(n, n - (n - 1) / 3, _pubKeyList);
    }

    /* @notice              Verify Poly chain consensus node signature
    *  @param _rawHeader    Poly chain block header raw bytes
    *  @param _sigList      consensus node signature list
    *  @param _keepers      addresses corresponding with Poly chain book keepers' public keys
    *  @param _m            minimum signature number
    *  @return              true or false
    */
    function verifySig(bytes memory _rawHeader, bytes memory _sigList, address[] memory _keepers, uint256 _m)
        internal
        pure
        returns (bool)
    {
        bytes32 hash = getHeaderHash(_rawHeader);

        uint256 sigCount = _sigList.length / POLYCHAIN_SIGNATURE_LEN;
        address[] memory signers = new address[](sigCount);
        bytes32 r;
        bytes32 s;
        uint8 v;
        for (uint256 j = 0; j < sigCount; j++) {
            r = Utils.bytesToBytes32(Utils.slice(_sigList, j * POLYCHAIN_SIGNATURE_LEN, 32));
            s = Utils.bytesToBytes32(Utils.slice(_sigList, j * POLYCHAIN_SIGNATURE_LEN + 32, 32));
            v = uint8(_sigList[j * POLYCHAIN_SIGNATURE_LEN + 64]) + 27;
            signers[j] = ecrecover(sha256(abi.encodePacked(hash)), v, r, s);
        }
        return Utils.containMAddresses(_keepers, signers, _m);
    }

    /* @notice               Serialize Poly chain book keepers' info in Ethereum addresses format into raw
    bytes
    *  @param keepersBytes   The serialized addresses
    *  @return               serialized bytes result
    */
    function serializeKeepers(address[] memory keepers) internal pure returns (bytes memory) {
        uint256 keeperLen = keepers.length;
        bytes memory keepersBytes = ZeroCopySink.WriteUint64(uint64(keeperLen));
        for (uint256 i = 0; i < keeperLen; i++) {
            keepersBytes =
                abi.encodePacked(keepersBytes, ZeroCopySink.WriteVarBytes(Utils.addressToBytes(keepers[i])));
        }
        return keepersBytes;
    }

    /* @notice               Deserialize bytes into Ethereum addresses
    *  @param keepersBytes   The serialized addresses derived from Poly chain book keepers in bytes format
    *  @return               addresses
    */
    function deserializeKeepers(bytes memory keepersBytes) internal pure returns (address[] memory) {
        uint256 off = 0;
        uint64 keeperLen;
        (keeperLen, off) = ZeroCopySource.NextUint64(keepersBytes, off);
        address[] memory keepers = new address[](keeperLen);
        bytes memory keeperBytes;
        for (uint256 i = 0; i < keeperLen; i++) {
            (keeperBytes, off) = ZeroCopySource.NextVarBytes(keepersBytes, off);
            keepers[i] = Utils.bytesToAddress(keeperBytes);
        }
        return keepers;
    }

    /* @notice               Deserialize Poly chain transaction raw value
    *  @param _valueBs       Poly chain transaction raw bytes
    *  @return               ToMerkleValue struct
    */
    function deserializeMerkleValue(bytes memory _valueBs) internal pure returns (ToMerkleValue memory) {
        ToMerkleValue memory toMerkleValue;
        uint256 off = 0;

        (toMerkleValue.txHash, off) = ZeroCopySource.NextVarBytes(_valueBs, off);

        (toMerkleValue.fromChainID, off) = ZeroCopySource.NextUint64(_valueBs, off);

        TxParam memory txParam;

        (txParam.txHash, off) = ZeroCopySource.NextVarBytes(_valueBs, off);

        (txParam.crossChainId, off) = ZeroCopySource.NextVarBytes(_valueBs, off);

        (txParam.fromContract, off) = ZeroCopySource.NextVarBytes(_valueBs, off);

        (txParam.toChainId, off) = ZeroCopySource.NextUint64(_valueBs, off);

        (txParam.toContract, off) = ZeroCopySource.NextVarBytes(_valueBs, off);

        (txParam.method, off) = ZeroCopySource.NextVarBytes(_valueBs, off);

        (txParam.args, off) = ZeroCopySource.NextVarBytes(_valueBs, off);
        toMerkleValue.makeTxParam = txParam;

        return toMerkleValue;
    }

    /* @notice            Deserialize Poly chain block header raw bytes
    *  @param _valueBs    Poly chain block header raw bytes
    *  @return            Header struct
    */
    function deserializeHeader(bytes memory _headerBs) internal pure returns (Header memory) {
        Header memory header;
        uint256 off = 0;
        (header.version, off) = ZeroCopySource.NextUint32(_headerBs, off);

        (header.chainId, off) = ZeroCopySource.NextUint64(_headerBs, off);

        (header.prevBlockHash, off) = ZeroCopySource.NextHash(_headerBs, off);

        (header.transactionsRoot, off) = ZeroCopySource.NextHash(_headerBs, off);

        (header.crossStatesRoot, off) = ZeroCopySource.NextHash(_headerBs, off);

        (header.blockRoot, off) = ZeroCopySource.NextHash(_headerBs, off);

        (header.timestamp, off) = ZeroCopySource.NextUint32(_headerBs, off);

        (header.height, off) = ZeroCopySource.NextUint32(_headerBs, off);

        (header.consensusData, off) = ZeroCopySource.NextUint64(_headerBs, off);

        (header.consensusPayload, off) = ZeroCopySource.NextVarBytes(_headerBs, off);

        (header.nextBookkeeper, off) = ZeroCopySource.NextBytes20(_headerBs, off);

        return header;
    }

    /* @notice            Deserialize Poly chain block header raw bytes
    *  @param rawHeader   Poly chain block header raw bytes
    *  @return            header hash same as Poly chain
    */
    function getHeaderHash(bytes memory rawHeader) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(sha256(rawHeader)));
    }
}
