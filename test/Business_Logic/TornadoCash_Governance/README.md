# Exploited Protocol Name
- **Type:** Exploit
- **Network:** Mainnet
- **Total lost:** ~2.5MM USD 
- **Category:**  Business Logic - Proposal Code Validation
- **Vulnerable contracts:**
- - [Tornado Cash Governance](https://etherscan.io/address/0x5efda50f22d34f262c29268506c5fa42cb56a1ce#code)
- **Tokens Lost**
- - TORN ~ 1,000,000 (10,000 torn per account, used 100 accounts)

- **Attack transactions:**
- **Step 0**
- - [Proposal Factory Deploy - Attacker 2](https://etherscan.io/tx/0x3e93ee75ffeb019f1d841b84695538571946fd9477dcd3ecf0790851f48fbd1a)
- - [Initial Torn Lock - Attacker 2](https://etherscan.io/tx/0xf93536162943bd36df11de6ed11233589bb5f139ff4e9e425cb5256e4349a9b4)
- **Step 1**
- - [Submit Proposal - Attacker 2](https://etherscan.io/tx/0x34605f1d6463a48b818157f7b26d040f8dd329273702a0618e9e74fe350e6e0d)
- **Step 2**
- - [Deploy multiple accounts - Attacker 1](https://etherscan.io/tx/0x26672ad9140d11b64964e79d0ed5971c26492786cfe0edf57034229fdc7dc529)
-  **Step 3**
- - [Destroy proposal - Attacker 2](https://etherscan.io/tx/0xd3a570af795405e141988c48527a595434665089117473bc0389e83091391adb)
-  **Step 4**
- - [Redeploy proposal - Attacker 2](https://etherscan.io/tx/0xa7d20ccdbc2365578a106093e82cc9f6ec5d03043bb6a00114c0ad5d03620122)
-  **Step 5**
- - [Execute proposal - Attacker 2](https://etherscan.io/tx/0x3274b6090685b842aca80b304a4dcee0f61ef8b6afee10b7c7533c32fb75486d)
-  **Step 6**
- - [Drain TORN - Attacker 1](https://etherscan.io/tx/0x13e2b7359dd1c13411342fd173750a19252f5b0d92af41be30f9f62167fc5b94)

- - Attacker 1 EOA: [0x592340957ebc9e4afb0e9af221d06fdddf789de9](https://etherscan.io/address/0x592340957ebc9e4afb0e9af221d06fdddf789de9)
- - Attacker 2 EOA: [0x092123663804f8801b9b086b03b98d706f77bd59](https://etherscan.io/address/0x092123663804f8801b9b086b03b98d706f77bd59)

- **Attack Block:**: From `17,248,593` up to `17,304,425`  
- **Date:** May 21, 2023
- **Reproduce:** `forge test --match-contract Exploit_TornadoCashForkFoundry -vvv`

## Step-by-step Overview
Two accounts played pivotal roles in the incident: Attacker 2 (Proposal Handler) and Attacker 1 (Drainer Controller). Attacker 2 was responsible for managing the proposal's life cycle including its deployment, submission, destruction, re-deployment, and execution. Attacker 1, on the other hand, controlled the drainer contracts which facilitated the unlocking of TORN from Tornado Cash.

### **Stage 0: Initial Transactions [Proposal Handler]**
Attacker 2 [withdrawn 10 ETH](https://etherscan.io/tx/0xf1f298d6168cac774cfe356a73380d29aed5429abc1ba785f162a59c85de7867) from Tornado Cash and then [swapped](https://etherscan.io/tx/0x82dca5a88a43377cab4748073a3a46c8aa120d42c5c5d802789cf17df22f0acd) these into 1017 TORN through `1inch`. Concurrently, a `proposal factory`, a `middle` or `transient` and a `proposal` contracts were deployed. Attacker 2 then locked the `1017 TORN` into the Tornado Cash Governance, enabling proposal submission.

### **Stage 1: Proposal Submission [Proposal Handler]**
With the `TORN` tokens now locked, Attacker 2 submitted the proposal to the Tornado Governance. This proposal was structured similarly to [Proposal #16](https://etherscan.io/address/0xd4b776caf2a39aeceb21a5dd7812082e2391b03d#code) but included a [`selfdestruct`](https://explorer.phalcon.xyz/tx/eth/0xd3a570af795405e141988c48527a595434665089117473bc0389e83091391adb?line=3&debugLine=3) instruction within an `emergencyStop` function.

### **Stage 2: Account Creation [Drainer Controller]**
Attacker 1 created 100 subsidiary accounts (minions), locking zero `TORN` balance in Tornado for each one. This last step is a pretty curious yet interesting one, as the attack could have succeeded even without any `TORN` approved and locked by those 100 subsidiary accounts.

### **Stage 3: Proposal Destruction [Proposal Handler]**
Attacker 2 triggered the `emergencyStop` from the factory before the proposal execution, leading to the destruction of both the `proposal` and the `transient` contract. This resets the nonce of the `transient` contract, thus allowing the modification of the `proposal's` implementation.

### **Stage 4: Redeployment [Proposal Handler]**
Attacker 2 then redeployed the `transient` and a new malicious `proposal` on the same addresses as before using `create2` and `create`, relying on the nonce reset of the previous step (relevant for `create`) and on the deterministic deployments via `create2`. More details about this step in the next section.

### **Stage 5: Locked Balance Modification [Proposal Handler]**
Upon proposal execution within the Tornado Cash's context (using `delegatecall`), Attacker 2 employed `sstore` instructions added into the new proposal's implementation to alter the `lockedBalance` mapping of the 100 accounts created by Attacker 1, assigning `10,000` locked `TORN` to each account.

### **Stage 6: Token Transfer [Drainer Controller]**
Once the balance of each minion account was updated, Attacker 1 initiated the `unlock` and `transfer` of `TORN` tokens, directing all the funds to their own account.

## Detailed Description

This attack relies on several important concepts such as different ways of deploying contracts (`create2` and `create`), context of execution (proposals are executed with `delegatecall`), mapping slot calculation (implemented in the malicious proposal). We will dissect them in this section.  


```solidity

```


## Possible mitigations

1. 

## Sources and references

- [Source](https://link_to_source)

