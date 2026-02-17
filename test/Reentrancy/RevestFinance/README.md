---
title: Revest Finance
description: Reentering token vault systems through ERC-1155 callbacks
type: Exploit
network: [ethereum]
date: 2022-03-27
loss_usd: 2000000
returned_usd: 0
tags: [reentrancy]
subcategory: []
vulnerable_contracts:
  - "0x2320A28f52334d62622cc2EaFa15DE55F9987eD9"
tokens_lost:
  - RENA
attacker_addresses:
  - "0xef967ECE5322c0D7d26Dab41778ACb55CE5Bd58B"
malicious_token: []
attack_block: [14465357]
reproduction_command: forge test --match-contract Exploit_RevestFinance -vvv
attack_txs:
  - "0xe0b0c2672b760bef4e2851e91c69c8c0ad135c6987bbf1f43f5846d89e691428"
sources:
  - title: BlocksecTeam Tweet
    url: https://twitter.com/BlockSecTeam/status/1508065573250678793
  - title: BlocksecTeam Article
    url: https://blocksecteam.medium.com/revest-finance-vulnerabilities-more-than-re-entrancy-1609957b742f
---

## Step-by-step

Each FNFT could be redeemed by the accounted tokens it backs. The attacker created vaults (repredented by FNFTs) without backing them with RENA and
reentered with depositToken which updates the vault's balance before doMint.

1. Mints first a small amount to determine the currentId and to generate a small NFT position.
2. Mints a big NFT position and reenters the minting call with `revest.depositAdditionalToken()` with just 1e18 RENA so each token virtually backs that amount.
3. After the call finishes, the internal accoutancy interprets that the attacker sent `360,000 * 1e18` RENA instead of what he sent allowing him to redeem that amount of RENA.

## Detailed Description

The attacker managed to reenter the minting mechanism of the ERC-1155's with its callback.

```solidity
   function mintAddressLock(
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable override returns (uint) {
        uint fnftId = getFNFTHandler().getNextId();

        {
            IRevest.LockParam memory addressLock;
            addressLock.addressLock = trigger;
            addressLock.lockType = IRevest.LockType.AddressLock;
            // Get or create lock based on address which can trigger unlock, assign lock to ID
            uint lockId = getLockManager().createLock(fnftId, addressLock);

            if(trigger.supportsInterface(ADDRESS_LOCK_INTERFACE_ID)) {
                IAddressLock(trigger).createLock(fnftId, lockId, arguments);
            }
        }
        // This is a public call to a third-party contract. Must be done after everything else.
        // Safe for reentry
        doMint(recipients, quantities, fnftId, fnftConfig, msg.value);

        emit FNFTAddressLockMinted(fnftConfig.asset, _msgSender(), fnftId, trigger, quantities, fnftConfig);

        return fnftId;
    }

    // Then, doMint call ends up calling tokenVault.depositToken():

    function depositToken(
        uint fnftId,
        uint transferAmount,
        uint quantity
    ) public override onlyRevestController {
        // Updates in advance, to handle rebasing tokens
        updateBalance(fnftId, quantity * transferAmount); // <----- HERE IS WHERE THE LOCKED BALANCE OF THE NFT IS ACCOUNTED
        IRevest.FNFTConfig storage fnft = fnfts[fnftId];
        fnft.depositMul = tokenTrackers[fnft.asset].lastMul;
    }

    // In revest.depositAdditionalToken(), the balance of an NFT is topped up with more tokens:
    function depositAdditionalToFNFT(
        uint fnftId,
        uint amount,
        uint quantity
    ) external override returns (uint) {
        ...
        ITokenVault(vault).depositToken(fnftId, amount, quantity);
        ...
    }

    // The FNFT Token Handler's mint function does not respect the Checks-Effects-Interactions pattern minting before updating internal variables.

    function mint(address account, uint id, uint amount, bytes memory data) external override onlyRevestController {
        supply[id] += amount;
        _mint(account, id, amount, data);
        fnftsCreated += 1;
    }
```

1. The deposit flow does not ensure that the token addresses provided match the addresses of the pools that are called (\_pid)
2. The liquidity and internal balances (vars) are updated after adding liquidity inside addLiquidityInternal().
3. Because of 1. and 2., the deposit flow could be attacked by reentrancy as tokens flow before updating key variables and the pools allow malicious tokens.
   The deposit flow will update twice the balance of the attacker contract (malicious token) transferring the double of stablecoins.

## Possible mitigations

- Respect the checks-effects-interactions security pattern by minting tokens lastly on the mint call
- Evaluate if checks are needed before minting in order to guarantee that the system works as intended (e.g. no checks present in the mint function).

## Related

- [Paraluni](/learn-evm-attacks/cases/paraluni/) - Reentrancy through malicious token callbacks
- [Fei Protocol](/learn-evm-attacks/cases/fei-protocol/) - Cross-function reentrancy in lending protocol
- [Cream Finance](/learn-evm-attacks/cases/cream-finance/) - Reentrancy through token hooks bypassing per-contract mutex
