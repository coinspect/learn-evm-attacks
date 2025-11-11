---
title: "LyraDepositWrapper"
description: "Missing validation on zero-amount deposit and arbitrary socketVault allows unauthorized fund approval and transfer."
type: Exploit
network: ["ethereum"]
date: 2025-09-16
loss_usd: 1000000 
returned_usd: 0 
tags: [data validation, bridges]
subcategory: []
vulnerable_contracts:
    - "0x18a0f3F937DD0FA150d152375aE5A4E941d1527b"
tokens_lost:
    - "USDC"
attacker_addresses:
    - "0x62005500Af4CFB0077AC0090002F630055Ba001D"
malicious_token: []
attack_block: [23377073]
attack_txs:
    - "0xc2bab117b6cb95e12c14eb57deb2cdd592370e2eb614e6d37502dea1480db0ba"
reproduction_command: "forge test --match-contract Exploit_LyraDepositWrapper -vvv" # 

sources:
    - title: "TenArmorAlert"
      url: "https://x.com/TenArmorAlert/status/1968138774551969874"
    - title: "Blockthreat"
      url: "https://newsletter.blockthreat.io/i/174288580/lyradepositwrapper"
    - title: "Quadriga Initiative"
      url: "https://www.quadrigainitiative.com/casestudy/lyradepositwrapper.php"
---

## Step-by-step

This exploit was a combination of user error and a vulnerability in the `LyraDepositWrapper` contract. A MEV bot was able to drain $1 million in `USDC` after a user accidentally transferred the funds directly to the contract address instead of using its intended deposit function.

1.  **User Error (Pre-condition):** A user, funded from the FalconX exchange, mistakenly sent $1,000,000 USDC directly to the `LyraDepositWrapper` contract address. This action did not trigger any contract logic and left the funds in the contract's balance.
2.  **Vulnerability Discovery:** A MEV bot detected this balance in the contract.
3.  **Exploitation:** The bot called the `depositToLyra()` function with:
    *   `amount`: `0`
    *   `socketVault`: The attacker's own address.
4.  **Arbitrary Approval:** The function's logic bypassed the initial token transfer because the amount was zero, but proceeded to grant an unlimited USDC approval to the attacker's address (`socketVault`).
5.  **Draining Funds:** With the approval granted, the attacker immediately called `transferFrom` on the USDC contract to pull the entire $1M balance from the `LyraDepositWrapper` to their own wallet.

## Detailed Description

The vulnerability existed within the `depositToLyra` function, which lacked validation checks. The function was designed to transfer tokens from a user, approve a `socketVault` for bridging, and then initiate the deposit.

```solidity
function depositToLyra(
    address token,
    address socketVault,
    bool isSCW,
    uint256 amount,
    uint256 gasLimit,
    address connector
) external payable {
    //  If `amount` is 0,  transferFrom does not revert.
    IERC20(token).transferFrom(msg.sender, address(this), amount);
    
    // The `socketVault` parameter is not validated and can be any address.
    IERC20(token).approve(socketVault, type(uint256).max);

    address recipient = _getL2Receiver(isSCW);

    ISocketVault(socketVault).depositToAppChain{value: msg.value}(recipient, amount, gasLimit, connector);
}
```
__LyraDepositWrapper.sol__

The attack was possible due to unvalidated approval, The function immediately proceeded to `IERC20(token).approve(socketVault, type(uint256).max)`. Since the `socketVault` parameter was controlled by the caller and not validated against a whitelist of trusted addresses, the attacker could simply provide their own address.


```solidity
LYRA_DEPOSIT_WRAPPER.depositToLyra{value: 0}(
    address(USDC),
    ATTACKER, // socketVault: The address to grant approval to.
    false,
    0,        // amount: Bypasses the transferFrom.
    1,
    address(WETH)
);
```
__LyraDepositWrapper.attack.sol__

The final step was a simple `transferFrom` call to drain the $1 million that the user had mistakenly deposited.


## Possible mitigations

- **Whitelist Addresses:** The `socketVault` parameter should not have been an arbitrary address. The contract should maintain a whitelist of trusted vault addresses.

- **Input Validation:** The fix is to validate inputs properly. The function should have required the deposit amount to be greater than zero.

