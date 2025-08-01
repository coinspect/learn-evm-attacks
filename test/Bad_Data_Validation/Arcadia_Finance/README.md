---
title: Arcadia Finance
type: Exploit
network: Base
date: 2025-07-14
loss_usd: 3600000
category: Data validation
vulnerable_contracts:
  - https://basescan.org/address/0xC729213B9b72694F202FeB9cf40FE8ba5F5A4509#code
attacker_addresses:
  - title: Exploiter's EOA
    url: https://basescan.org/address/0x0fa54e967a9cc5df2af38babc376c91a29878615
  - title: Attacker's Smart Contract 1
    url: https://basescan.org/address/0x6250dfd35ca9eee5ea21b5837f6f21425bee4553
  - title: Attacker's Smart Contract 2
    url: https://basescan.org/address/0x1DBC011983288B334397B4F64c29F941bE4DF265
attack_block: 32881499
reproduction_command: forge test --match-contract Exploit_ArcadiaFinance -vvv --via-ir
attack_txs:
  - https://basescan.org/tx/0x0b2b055a4900a8b6c1f21e7c188811e0d67ead3eaa6f7c2c5242f0d4817b32e0
  - https://basescan.org/tx/0x23c3796c42dbca0148975729a5f2dddf539c4c7a8284289e12190fbd5a6c091b
  - https://basescan.org/tx/0x38b744e967e6d6ed8870619ac2f35b6d5612a396eaf3ba981ed754c7395c310d
  - https://basescan.org/tx/0xd384589bae3deeb147df65d26ce1e9e8d2386ebbd7b4a2a5018161e766e4c625
  - https://basescan.org/tx/0x28b20fb13d0f0df428da076a25e5ae9c889a17cfa7a5b463ae477c47d855e5d1
  - https://basescan.org/tx/0xeb1cbbe6cf195d7e23f2c967542b70031a220feacca010f5a35c0046d1a1820a
  - https://basescan.org/tx/0x06ce76eae6c12073df4aaf0b4231f951e4153a67f3abc1c1a547eb57d1218150
  - https://basescan.org/tx/0x0b9bed09d241cef8078e6708909f98574c33ee06abcc2f80bc41731cd462d60b
---

## Step-by-step Overview

1. Bait Phase:
    - The attacker deployed two contracts that triggered ArcadiaFi's automated circuit breakers, pausing the protocol (https://basescan.org/tx/0x0b2b055a4900a8b6c1f21e7c188811e0d67ead3eaa6f7c2c5242f0d4817b32e0 , https://basescan.org/tx/0x23c3796c42dbca0148975729a5f2dddf539c4c7a8284289e12190fbd5a6c091b).
    - The team investigated and found no immediate threat, leading them to unpause the protocol (https://basescan.org/tx/0x38b744e967e6d6ed8870619ac2f35b6d5612a396eaf3ba981ed754c7395c310d).
    - After unpausing, the protocol entered a cooldown period where it cannot be paused again for a specified time window, leaving it vulnerable during this period.

2. Setup:
    - Attacker deployed multiple exploit contracts designed to interact with the Arcadia Protocol (https://basescan.org/tx/0xd384589bae3deeb147df65d26ce1e9e8d2386ebbd7b4a2a5018161e766e4c625, https://basescan.org/tx/0x28b20fb13d0f0df428da076a25e5ae9c889a17cfa7a5b463ae477c47d855e5d1).
    - Created multiple Arcadia accounts that would be used for the attack execution (https://basescan.org/tx/0xeb1cbbe6cf195d7e23f2c967542b70031a220feacca010f5a35c0046d1a1820a).

3. Attack Execution:
    - The attacker took three Morpho flashloans totaling approximately $1.5 billion to obtain sufficient capital (https://basescan.org/tx/0x06ce76eae6c12073df4aaf0b4231f951e4153a67f3abc1c1a547eb57d1218150).
    - Linked the Asset Manager to his own account, designating himself as the initiator to gain control over rebalancing operations.
    - Created a small LP position.
    - Repaid the debt of the target account to manipulate its health status.
    - Triggered a rebalance operation for his own LP position, injecting malicious custom calldata instead of standard swap parameters.
    - Exploited missing validation in the rebalancing mechanism to execute an arbitrary call to the victim's Arcadia Account. This allowed the attacker to hijack the `msg.sender` of the Rebalancer contract (Asset Manager) and execute `flashAction` in the target account, enabling him to withdraw remaining funds.
    - Since the target account had no debt left, the account remained healthy, allowing the attacker to withdraw all funds without triggering any health checks.
    - Repayed the flashloan debt.
    - Kept remaining funds.
    - Repeated the process with multiple target accounts.

## Detailed Description

### Root Cause

The root cause of the exploit lies in the `_swapViaRouter` function of the `RebalancerSpot` contract, where an arbitrary external call is executed based on user input without proper validation.

The attacker could hijack the `msg.sender` context of the Asset Manager to call target Arcadia Accounts that had authorized the Asset Manager as an allowed asset manager. This created a privilege escalation scenario.

In Arcadia's architecture, "Account" addresses have special permissions that allow them to call protected methods such as the `rebalance` function in the `RebalancerSpot` contract. The attack worked when the `router` parameter was not a legitimate router but an "Account" registered in the system.

This design flaw allowed the attacker to execute an arbitrary call to rebalance a position mid-execution in a malicious manner. The `_swapViaRouter` function's lack of validation on the router address meant that any registered Account could be used as a router, enabling the attacker to abuse the trust relationship between the Asset Manager and victim Accounts.

The vulnerable code section shows how the call is executed to an arbitrary address with arbitrary data because `swapData` is completely controlled by the attacker:

```solidity
function _swapViaRouter(
    address positionManager,
    Rebalancer.PositionState memory position,
    bool zeroToOne,
    bytes memory swapData
) internal returns (uint256 balance0, uint256 balance1) {
    // Decode the swap data.
    (address router, uint256 amountIn, bytes memory data) = abi.decode(swapData, (address, uint256, bytes));

    //...

    // Execute arbitrary swap.
    (bool success, bytes memory result) = router.call(data);
    require(success, string(result));

    //...

}
```

### Attack Overview

The attacker deployed two contracts that triggered Arcadia Finance's automated circuit breakers, pausing the protocol. When the team investigated and found no threat, they unpaused the protocol. This created a cooldown period during which the protocol could not be paused again, providing a guaranteed execution window.

After that, the attacker deployed multiple exploit contracts designed to interact with the Arcadia Protocol and created multiple Arcadia accounts for use in the attack.

The attacker obtained approximately $1.5 billion through three sequential Morpho flashloans (`USDC`, `WETH`, and `cbBTC`). The flashloans were chained together using the `onMorphoFlashLoan` callback function, where each callback would initiate the next `flashloan` call until all three tokens were borrowed. This capital was required for manipulating the protocol's state and repaying victim account debts.

Using one of his previously created accounts, the attacker linked the `RebalancerSpot` contract as an Asset Manager, designating himself as the `initiator` to gain control over rebalancing operations.

```solidity
IAccount(accounts[0]).setAssetManager(rebalancerSpot, true);

IRebalancerSpot(rebalancerSpot).setAccountInfo(
    accounts[0], // account,
    address(this), // initiator,
    exploitHook // hook
);
```

The attacker created a liquidity position and deposited it into the attacker's Arcadia account along with additional `USDC` and `cbBTC` tokens. This position served as the entry point for the malicious rebalancing operation.

```solidity
(uint256 tokenId,_,_,_) = nonFungiblePositionManagerAERO_CL_POS.mint(mintParams);

nonFungiblePositionManagerAERO_CL_POS.setApprovalForAll(
    accounts[0],
    true
);

address[] memory assetAddresses = new address[](3);
assetAddresses[0] = address(nonFungiblePositionManagerAERO_CL_POS);
assetAddresses[1] = address(USDC);
assetAddresses[2] = address(cbBTC);

uint256[] memory assetIds = new uint256[](3);
assetIds[0] = tokenId;
assetIds[1] = 0;
assetIds[2] = 0;

uint256[] memory assetAmounts = new uint256[](3);
assetAmounts[0] = 1;
assetAmounts[1] = 10000000;
assetAmounts[2] = 100000000;

// Deposit assets into the account
IAccount(accounts[0]).deposit(
    assetAddresses,
    assetIds,
    assetAmounts
);
```

The attacker used the flashloan capital to repay the victim's account `cbBTC` debt. This placed the victim account in a healthy state, preventing safety mechanisms from triggering during fund extraction:

```solidity
arcadiaLendingPoolcbBTC.repay(
    wbtcWithdrawable,
    address(targetAccount)
);
```

Finally, the attacker triggered a rebalance operation in his own account by calling `rebalance()` with carefully crafted parameters:

```solidity
bytes memory swapData = getSwapData();

IRebalancerSpot(rebalancerSpot).rebalance(
    address(accounts[0]),
    address(nonFungiblePositionManagerAERO_CL_POS),
    tokenId,
    -81100,
    -80100,
    swapData
);
```

The function was called with the attacker's Arcadia account, position manager address for his LP position, the token ID, new tick range, and most importantly, the malicious swap data.

Instead of rebalancing through a DEX aggregator, the attacker used custom calldata to abuse missing validation and call the victim's Arcadia Account from within the Asset Manager context, making it appear as if the Asset Manager itself initiated the call.

```solidity
function _swapViaRouter(
    address positionManager,
    Rebalancer.PositionState memory position,
    bool zeroToOne,
    bytes memory swapData
) internal returns (uint256 balance0, uint256 balance1) {
    // Decode the swap data.
    (address router, uint256 amountIn, bytes memory data) = abi.decode(swapData, (address, uint256, bytes));

    //...

    // Execute arbitrary swap.
    (bool success, bytes memory result) = router.call(data);
    require(success, string(result));

    //...

}
```

The attacker hijacked the `msg.sender` context of the Asset Manager and executed arbitrary code in the victim's account.

The malicious swap data contained the victim account address as the router and calldata to execute the victim's `flashAction` function. Flash actions are Arcadia's mechanism that allows accounts to optimistically withdraw assets, execute external logic (such as swaps or DeFi interactions), and deposit tokens back into the account. The only requirement is that the account must remain healthy (collateral exceeds liabilities) at the end of the operation.

The attacker exploited this by encoding `actionTarget` and `actionData` that executed withdrawal functions in the victim's account. Since the victim account had no remaining debt after the attacker's earlier repayment, it would pass the health check despite the fund withdrawal, allowing the attacker to extract all remaining assets.

```solidity
function flashAction(address actionTarget, bytes calldata actionData)
    external
    onlyAssetManager
    nonReentrant
    notDuringAuction
    updateActionTimestamp
{
    // Decode flash action data.
    (
        ActionData memory withdrawData,
        ActionData memory transferFromOwnerData,
        IPermit2.PermitBatchTransferFrom memory permit,
        bytes memory signature,
        bytes memory actionTargetData
    ) = abi.decode(actionData, (ActionData, ActionData, IPermit2.PermitBatchTransferFrom, bytes, bytes));

    // Withdraw assets to the actionTarget.
    _withdraw(withdrawData.assets, withdrawData.assetIds, withdrawData.assetAmounts, actionTarget);

    //...

    // Execute external logic on the actionTarget.
    ActionData memory depositData = IActionBase(actionTarget).executeAction(actionTargetData);

    //...

    // Account must be healthy after actions are executed.
    if (isAccountUnhealthy()) revert AccountErrors.AccountUnhealthy();
}
```

The exploited call chain looks like this:

1. `RebalancerSpot.rebalance(controlled_data)` - Initiated by the attacker's account
2. `Account1.flashAction(partially_controlled_data)` - Regular functionality of the protocol
3. `RebalancerSpot.executeAction(controlled_data)` - Re-entered through the flashAction
4. `RebalancerSpot._swapViaRouter(positionManager, position, zeroToOne, fully_controlled_data)` - Executes arbitrary call with controlled data
5. `VictimAccount.flashAction(fully_controlled_data)` - Final call to victim account that withdraws funds

This chain was possible because `RebalancerSpot.executeAction` is only callable by an Account, and `Account.flashAction` is only callable by the `RebalancerSpot`. The attacker gained progressively more control over execution flow through each call.

After extracting funds, the attacker executed a series of swaps to repay the flashloans. The remaining tokens were approved for withdrawal by the original exploiter address.

This process was repeated multiple times using different victim addresses and accounts, allowing the attacker to drain a total of approximately $3.6 million in assets.

## Possible mitigations

- Strict Input Validation: a check should be performed to ensure the router address is not an Arcadia Account, or ideally, it should be restricted to a pre-approved whitelist of legitimate DEX routers.

- Use Intermediary Contracts: use an intermediate, isolated smart contract with no special permissions on Arcadia's core contracts to handle external interactions like swaps. This would prevent the msg.sender context of privileged contracts from being hijacked.

## Sources and references

- [Rekt](https://rekt.news/arcadiafi-rekt)
- [Arcadia PostMortem](https://arcadiafinance.notion.site/Arcadia-Post-Mortem-14-07-2025-23104482afa780fdb291cd3f41b7fc99)
- [PashovAuditGroup Tweet](https://x.com/PashovAuditGrp/status/1945467861654290433)