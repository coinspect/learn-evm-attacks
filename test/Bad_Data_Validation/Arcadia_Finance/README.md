# Arcadia Finance

- **Type:** Exploit
- **Network:** Base
- **Total lost:** ~ 3.6 million USD
- **Category:** Data validation
- **Vulnerable contracts:**
    - [Rebalancer Spot](https://basescan.org/address/0xC729213B9b72694F202FeB9cf40FE8ba5F5A4509#code)
    - [Target Account](https://basescan.org/address/0x9529e5988ced568898566782e88012cf11c3ec99#code)

- **Attack transactions:**

    - Bait Phase:

    

    - Main Attack:

- **Attacker Addresses:**

    - Exploiter's EOA: [0x0fa54e967a9cc5df2af38babc376c91a29878615](https://basescan.org/address/0x0fa54e967a9cc5df2af38babc376c91a29878615)

    - Attacker's Smart Contract 1: [0x6250dfd35ca9eee5ea21b5837f6f21425bee4553](https://basescan.org/address/0x6250dfd35ca9eee5ea21b5837f6f21425bee4553)

    - Attacker's Smart Contract 2: [0x1DBC011983288B334397B4F64c29F941bE4DF265](https://basescan.org/address/0x1DBC011983288B334397B4F64c29F941bE4DF265)

- **Attack Block:**: 32881499 (First attack transaction to drain funds)
- **Date:** July 14, 2025
- **Reproduce:** `forge test --match-contract Exploit_ArcadiaFinance -vvv --via-ir`

## Step-by-step Overview

1. Bait Phase:
    - The attacker deployed two contracts that triggered ArcadiaFi's automated circuit breakers, pausing the protocol.
    - The team investigated and found no immediate threat, leading them to unpause the protocol.
    - After unpausing, the protocol entered a cooldown period where it cannot be paused again for a specified time window, leaving it vulnerable during this period.

2. Setup:
    - Attacker deployed multiple exploit contracts designed to interact with the Arcadia Protocol.
    - Created multiple Arcadia accounts that would be used for the attack execution.

3. Attack Execution:
    - The attacker took three Morpho flashloans totaling approximately $1.5 billion to obtain sufficient capital.
    - Linked the Asset Manager to his own account, designating himself as the initiator to gain control over rebalancing operations.
    - Created a small LP position.
    - Repaid the debt of the target account to manipulate its health status.
    - Triggered a rebalance operation for his own LP position, injecting malicious custom calldata instead of standard swap parameters.
    - Exploited missing validation in the rebalancing mechanism to execute an arbitrary call to the victim's Arcadia Account. This allowed the attacker to hijack the `msg.sender` of the Rebalancer contract (Asset Manager) and execute `flashAction` in the target account, enabling him to withdraw remaining funds.
    - Since the target account had no debt left, the account remained healthy, allowing the attacker to withdraw all funds without triggering any health checks.
    - Repayed the flashloan debt.
    - Kept remaining funds.

## Detailed Description

### Root Cause

### Attack Overview

## Possible mitigations

## Sources and references

- [Rekt](https://rekt.news/arcadiafi-rekt)
- [Arcadia PostMortem](https://arcadiafinance.notion.site/Arcadia-Post-Mortem-14-07-2025-23104482afa780fdb291cd3f41b7fc99)
- [PashovAuditGroup Tweet](https://x.com/PashovAuditGrp/status/1945467861654290433)