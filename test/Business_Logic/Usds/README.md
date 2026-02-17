---
title: Sperax USD (USDS)
description: Abusing contract deployment timing to bypass balance checks
type: Exploit
network: [arbitrum]
date: 2023-02-03
loss_usd: 309000
returned_usd: 0
tags: [business logic, migration process, arithmetic]
subcategory:
  - Faulty Migration Process
  - Balance Accounting
vulnerable_contracts:
  - "0x97A7E6Cf949114Fe4711018485D757b9c4962307"
tokens_lost:
  - USDS
attacker_addresses:
  - "0x4afcd19bb978eaf4f993814298504ed285df1181"
  - "0x5c978df5f8af72298fe1c2c8c2c05476a10f2539"
malicious_token: []
attack_block: [57803397]
reproduction_command: forge test --match-contract Exploit_Usds -vvv
attack_txs:
  - "0xfaf84cabc3e1b0cf1ff1738dace1b2810f42d98baeea17b146ae032f0bdf82d5"
  - "0xe74641b4b7e9c9eb7ab46082f322efbc510b8d39af609d934f41c41d7057fe49"
sources:
  - title: Sperax Post Mortem
    url: https://medium.com/sperax/usds-feb-3-exploit-report-from-engineering-team-9f0fd3cef00c
  - title: danielvf
    url: https://twitter.com/danielvf/status/1621965412832350208?s=20
---

## Step-by-step

1. Precalculate a contract address
2. Transfer some USDS to that precalculated address
3. Deploy the contract at the calculated address
4. Transfer a USDS token from the contract to update its balance and trigger the rebase bug

## Detailed Description

The USDS contract used the `Address.isContract()` library function to determine if an account is a contract. However, this check is conceptually wrong as it only works properly for already **deployed** contracts.

The implementation of `isContract()` is the following:

```solidity
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }
```

If `isContract` returns false, it does not assures that the address checked won't have deployed code across its lifecycle. Some examples that return false when calling `isContract`:

- an externally-owned account
- a contract in construction
- an address where a contract will be created (precalculated)
- an address where a contract lived, but was destroyed (could be abused by destroying + create2 to the same address)

The attacker precalculated the address of a Gnosis Safe and transferred funds to that precalculated address before. The token balances essentially are mappings that relate `address => amounts`, meaning that regardless the nature of that address or existence, it assigns balance to that account.

By sending tokens to an address that is not a contract (yet), the attacker managed to enter several conditional branches that were meant to be accessed by external accounts, getting a considerable amount of balance:

```solidity
    function _isNonRebasingAccount(_account) internal returns(bool){
        bool isContract = AddressUpgradeable.isContract(_account);
        if (isContract && rebaseState[_account] == RebaseOptions.NotSet) {
            _ensureRebasingMigration(_account);
        }
        return nonRebasingCreditsPerToken[_account] > 0;
    }

    function _ensureRebasingMigration(address _account) internal {
        if (nonRebasingCreditsPerToken[_account] == 0) {
            nonRebasingCreditsPerToken[_account] = 1;
            if (_creditBalances[_account] != 0) {
                // Update non rebasing supply
                uint256 bal = _balanceOf(_account);
                nonRebasingSupply = nonRebasingSupply.add(bal);
                _creditBalances[_account] = bal;
            }
        }
    }

    function _balanceOf(address _account) private view returns(uint256){
        uint256 credits = _creditBalance[_account];
        if (credits > 0) {
            if (nonRebasingCreditsPerToken[_account] > 0) {
                return credits;
            }
            return credits.dividePrecisely(rebasingCreditsPerToken);
        }
        return 0;
    }
```

The address bypass allows the attacker to generate balance in a 'non contract' account. Later, once the contract is deployed, the first transfer assigns the attackers `nonRebasingCreditsPerToken[_account] = 1` inside `_ensureRebasingMigration()`. Then, when calculating its balance it does not divide the amount of `credits` by `rebasingCreditsPerToken` and simply returns the amount of `credits` without rebasing.

The attacker managed to swap an equivalent of ~309K USD.

## Possible mitigations

Never rely on `isContract` or similar to check that an address will never be a contract across it's lifecycle.

## Related

- [Team Finance](/learn-evm-attacks/cases/team-finance/) - Exploiting migration processes with malicious token manipulation
- [TempleDAO Spoof Old Staking Contract](/learn-evm-attacks/cases/templedao-spoof-old-staking-contract/) - Spoofing contracts in migration flows
- [TornadoCash Governance Takeover](/learn-evm-attacks/cases/tornadocash-governance-takeover/) - Exploiting `create2` and contract deployment mechanics
