# Team Finance
- **Type:** Exploit
- **Network:** Ethereum Mainnet
- **Total lost:** ~15MM USD ($7MM where returned afterwards)
- **Category:** Business Logic - Faulty Migration Process
- **Vulnerable contracts:**
- - [Exploited Contract Implementation](https://etherscan.io/address/0x48d118c9185e4dbafe7f3813f8f29ec8a6248359#code)
- - [Exploited Contract Proxy](https://etherscan.io/address/0xE2fE530C047f2d85298b07D9333C05737f1435fB#code)
- - [V3 Migrator Proxy Deployment](https://etherscan.io/tx/0x350dd9d6cdaba277af927345b7f1421d60b84601f7271799157204f3993766d2#eventlog)
- **Tokens Lost**
- - 880 ETH
- - 642,932 DAI
- - 74,613,6575 CAW
- - 11,837,577 TSUKA
- **Attack transactions:**
- - [Attack Tx](https://etherscan.io/tx/0xb2e3ea72d353da43a2ac9a8f1670fd16463ab370e563b9b5b26119b2601277ce)

- - [Setup 1: lockToken()](https://etherscan.io/tx/0xe8f17ee00906cd0cfb61671937f11bd3d26cdc47c1534fedc43163a7e89edc6f)
- - Setup 2: extendLockDuration():
        [Id 15324](https://etherscan.io/tx/0x2972f75d5926f8f948ab6a0cabc517a05f0da5b53e20f670591afbaa501aa436),
        [Id 15325](https://etherscan.io/tx/0xec75bb553f50af37f8dd8f4b1e2bfe4703b27f586187741b91db770ad9b230cb),
        [Id 15326](https://etherscan.io/tx/0x79ec728612867b3d82c0e7401e6ee1c533b240720c749b3968dea1464e59b2c4),
        [Id 15327](https://etherscan.io/tx/0x51185fb580892706500d3b6eebb8698c27d900618021fb9b1797f4a774fffb04)
- **Attacker Addresses**: 
- - Deployer EOA: [0x161cebB807Ac181d5303A4cCec2FC580CC5899Fd](https://etherscan.io/address/0x161cebB807Ac181d5303A4cCec2FC580CC5899Fd)
- - Contract: [0xCFF07C4e6aa9E2fEc04DAaF5f41d1b10f3adAdF4](https://etherscan.io/address/0xCFF07C4e6aa9E2fEc04DAaF5f41d1b10f3adAdF4)
- - Malicious Token: [0x2d4ABfDcD1385951DF4317f9F3463fB11b9A31DF](https://etherscan.io/address/0x2d4ABfDcD1385951DF4317f9F3463fB11b9A31DF)
- **Attack Block:**: 15837165 
- **Date:** Oct 27, 2022
- **Reproduce:** `forge test --match-contract Exploit_TeamFinance -vvv`

## Step-by-step Overview

1. Get a Team Finance Lock NFT by providing malicious tokens
2. Extend the lock duration period of each NFT
3. Call `migrate()` using the Lock NFTs providing a migration target (V2 pair)
4. Swap and Transfer the loot to an external account


## Detailed Step-by-step 

The process has two main parts: The Setup and The Attack. 

### THE SETUP

The transactions performed on this part were made in order to bypass the initial checks of `migrate()`

1. Deploy a malicious inflationary token
2. Get Team Finance Lock NFTs:
     - Providing ETH to pay the fees
     - Setting the attacker's contract as the withdrawal address
     - Backing the NFT with the malicious token
3. Extend the duration of each NFT to sometime in the future


### THE ATTACK

Now that the TeamFinance Lock `migrate()` function is bypasseable by the attacker's contract and will also consider
the malicious tokens as additional liquidity provided.

1. Call `migrate()`:
   - For each NFT, target different V2 Pairs
   - On every migration use `sqrtPriceX96 = 79210883607084793911461085816`. This gets a price factor equal to 0.999563867 (*)
2. Exchange the loot for stablecoins using Curve, when applies
3. Send the loot to the external attacker's account

(*) Links and sources with more details on how this number is calculated, in the reproduction.


## Detailed Description

The main vulnerability being exploited is locking a custom token using the setup of the locking position to perform the migration
from a Uniswap V2 pool to a V3. The attacker bypassed the migration controls by using protocol's NFT lock positions backed by thes malicious token. 

```solidity
    function migrate(
        uint256 _id,
        IV3Migrator.MigrateParams calldata params,
        bool noLiquidity,
        uint160 sqrtPriceX96,
        bool _mintNFT
    )
    external
    payable
    whenNotPaused
    nonReentrant
    {
        ...
        Items memory lockedERC20 = lockedToken[_id];
        require(block.timestamp < lockedERC20.unlockTime, "Unlock time already reached");
        require(_msgSender() == lockedERC20.withdrawalAddress, "Unauthorised sender");
        require(!lockedERC20.withdrawn, "Already withdrawn");

        uint256 totalSupplyBeforeMigrate = nonfungiblePositionManager.totalSupply();
        
        //scope for solving stack too deep error
        {
            uint256 ethBalanceBefore = address(this).balance;
            uint256 token0BalanceBefore = IERC20(params.token0).balanceOf(address(this));
            uint256 token1BalanceBefore = IERC20(params.token1).balanceOf(address(this));
            
            //initialize the pool if not yet initialized
            if(noLiquidity) {
                v3Migrator.createAndInitializePoolIfNecessary(params.token0, params.token1, params.fee, sqrtPriceX96);
            }

            IERC20(params.pair).approve(address(v3Migrator), params.liquidityToMigrate);

            v3Migrator.migrate(params);

            //refund eth or tokens
            uint256 refundEth = address(this).balance - ethBalanceBefore;
            (bool refundSuccess,) = _msgSender().call.value(refundEth)("");
            require(refundSuccess, 'Refund ETH failed');

            uint256 token0BalanceAfter = IERC20(params.token0).balanceOf(address(this));
            uint256 refundToken0 = token0BalanceAfter - token0BalanceBefore;
            if( refundToken0 > 0 ) {
                require(IERC20(params.token0).transfer(_msgSender(), refundToken0));
            }

            uint256 token1BalanceAfter = IERC20(params.token1).balanceOf(address(this));
            uint256 refundToken1 = token1BalanceAfter - token1BalanceBefore;
            if( refundToken1 > 0 ) {
                require(IERC20(params.token1).transfer(_msgSender(), refundToken1));
            }
        }
        ...
        emit LiquidityMigrated(_msgSender(), _id, newDepositId, tokenId);
    }
```

Because the `migrate()` function refunds the difference after the migration, the attacker abused from this feature by manipulating the price
of the tokens involved on each pool.

The steps of **THE SETUP** bypass the `require` statements by:
   - Calling migrate after the extended period
   - Performing the migration from the attacker's contract
   - Not withdrawing the locked position

Due to the weakness of those checks, the attacker now is able to bypass the migration access control 
and specify any custom parameters in this process.

The attacker provided the `sqrtPriceX96` and also used the malicious tokens to inflate the price of each pool receiving outstanding refunds
draining the Lock contract via the migration process. 

## Possible mitigations

1. The most general recomendation for cases like this one: beware of user input parameters.
2. If the protocol allows users to provide arbitrary tokens to execute any type of logic, take into consideration
that malicious tokens of any nature could be provided (hookable, custom implemenations, inflatable, etc.). 
3. It is a good practise also, to set reasonable boundaries for some input parameters (such as the square root price)
even if a function is meant to be permissioned or called by specific users to mitigate any loss of access control (private key compromised, 
authentication bypass, etc).
4. Carefully review and check migration processes as they will likely be called once most likely conveying token transfers of considerable
amounts.


## Sources and references

- [Beiosin Analysis](https://medium.com/@Beosin_com/beosins-analysis-of-team-finance-s-13m-exploit-f0be090cce16)
- [Team Finance Official](https://twitter.com/TeamFinance_/status/1585770918873542656)
- [PeckShield](https://twitter.com/peckshield/status/1585587858978623491)
- [Solid Group Analysis](https://twitter.com/solid_group_1/status/1585643249305518083)
- [Beiosin Alert](https://twitter.com/BeosinAlert/status/1585578499125178369)
