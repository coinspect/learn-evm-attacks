# <h1 align="center"> Learn EVM Attacks </h1>
A collection of Foundry tests reproducing exploits, bug bounty reports, and theoretical vulnerabilities on EVM chains. Diagrams and context links accompany each attack reproduction to make it more helpful as a reference or study material for anyone trying to learn more about vulnerabilities in smart contract systems.

> [!IMPORTANT]  
> Some tests need access to archive data as they require state from old blocks. If a test is failing, make sure to set up an archive node as the JSON-RPC URL in `foundry.toml`. [Infura](https://docs.infura.io/api/networks/ethereum/concepts/archive-data) provides free access to archive data.

Want to take a quick look? Just go to a vulnerability folder (say, [MBCToken](/test/Access_Control/MBCToken)). Read the README or jump ahead to running the reproduction in your computer! You only need [Foundry](https://github.com/foundry-rs/foundry) installed. 

``` bash
$ git clone https://github.com/coinspect/learn-evm-attacks
$ forge install
$ forge test --match-contract Exploit_MBCToken -vvv
```

## Index

We now have 40 reproduced exploits. Of those 40, we have chosen a few in case you want to start studying up with some of the most interesting ones.

- **[Tornado Cash Governance Takeover](/test/Business_Logic/TornadoCash_Governance)** is an excellent way to show the dangers of `DELEGATECALL` and the perils of governance systems.
- **[Furucombo](/test/Business_Logic/Furucombo)** _another_ excellent way to show the dangers of `DELEGATECALL`.
- **[MBC Token](/test/Access_Control/MBCToken)** is a primer on how sandwich attacks can be made with an interesting backstory on suspicious tokenomics. 
- **[Uranium](/test/Business_Logic/Uranium)** is a great excuse to study up on the actual code that guards the famouse AMM constant product `x*y=k`.

To run an specific exploit, you can just use:

``` bash
forge test --match-contract Exploit_MBCToken -vvv
```

Vary the amount of verbosity (`-v`, `-vv`...) according to the data you want. `-vvvv` includes traces! 

The full list is below:

### Access Control
- [TempleDAO, Oct 2022 - (~$2.3MM) - Unchecked ownership on token migration](/test/Access_Control/TempleDao)
- [Rikkei, Apr 2022 - ($1MM) - Public Oracle Setter](/test/Access_Control/Rikkei)
- [DAOMaker, Sept 2021 - (~$4MM) - Public Init](/test/Access_Control/DAOMaker)
- [Sandbox, Feb 2022 - (1 NFT, possibly more) - Public Burn](/test/Access_Control/Sandbox)
- [Punk Protocol, Aug 2021 - (~$8MM) - Non initialized contract](/test/Access_Control/PunkProtocol)
- [MBC Token, Nov 2022 - (~$8MM) - External function](/test/Access_Control/MBCToken)

### Bad Data Validation
- [Olympus DAO Bond, Oct 2022 - (~$300,000) - Arbitrary Tokens / Unchecked transfers](/test/Bad_Data_Validation/Bond_OlympusDAO/)
- [Bad Guys NFT, Sept 2022 - (400 NFTs) - Unchecked Mint Amount](/test/Bad_Data_Validation/Bad_Guys_NFT/)
- [Multichain a.k.a AnySwap, Jan 2022 - (~$960,000) - Arbitrary Tokens / Unchecked Permit](/test/Bad_Data_Validation/Multichain_Permit/)
- [Superfluid, Jan 2022 - (~$8.7MM) - Calldata crafting / CTX not verified](/test/Bad_Data_Validation/Superfluid)
- [1inch, Mar 2025 - (~$5MM / ~$4.5MM returned) - Calldata Crafting / Unchecked Interaction Length](/test/Bad_Data_Validation/1inch/)

### Business Logic
- [Sperax USDS, Feb 2023 - (9.7B tokens / ~$309K) - Faulty Migration Process & Balance Accounting](/test/Business_Logic/Usds)
- [TeamFinance - Oct 2022 - (~$15MM / $7MM returned) - Arbitrary Input Parameters / Migrate Authentication Bypass](/test/Business_Logic/Team_Finance)
- [EarningFarm, Oct 2022 - (200 ETH) - Unchecked Flashloan reception](/test/Business_Logic/EarningFarm)
- [BVaults, Oct 2022 - ($35,000) - DEX Pair Manipulation](/test/Business_Logic/Bvaults)
- [Fantasm Finance, Mar 2022 - ($2.4MM) - Unchecked Payments While Minting](/test/Business_Logic/Fantasm_Finance/)
- [Compound - Mar 2022 - ($0) - Side Entrance on cToken](/test/Business_Logic/Compound/)
- [OneRing Finance - Mar 2022 - (~$2MM) - Price Feed Manipulation](/test/Business_Logic/OneRingFinance)
- [Vesper Rari Pool - Nov 2021 - (~$3MM) - Price Feed Manipulation](/test/Business_Logic/VesperRariFuse)
- [Uranium - Apr 2021 - (~$50MM) - Wrong Constant Product AMM checks](/test/Business_Logic/Uranium)
- [Furucombo - Feb 2021 - ($15MM) - DELEGATECALL to proxy](/test/Business_Logic/Furucombo)
- [Seaman - Nov 2022 - ($7K) - Sandwich attack](/test/Business_Logic/Seaman/)
- [Tornado Cash Governance - May 2023 - (~$2.7MM) - Malicious Proposal](/test/Business_Logic/TornadoCash_Governance)
- [Onyx Protocol - Nov 2023 - (~$2.1MM) - Empty Market Manipulation / Rounding Error](/test/Business_Logic/OnyxProtocol)
- [Polter Finance - Nov 2024 - (~$8.7MM) - Oracle Manipulation](/test/Business_Logic/Polter_Finance/)
- [SIR Trading - Mar 2025 - (~$355k) - Bad Usage of Transient Storage](/test/Business_Logic/SIRTrading/)
- [MobiusDAO - Mar 2025 - (~$2.15MM) - Bad Arithmetic](/test/Business_Logic/MobiusDAO/)
- [Cork Finance - May 2025 - (~$7.2MM) - Price Manipulation + Poor Access Control](/test/Business_Logic/Cork_Finance/)
- [Bunni V2 - Sept 2025 - (~$8.4MM) - Rounding Error + Price Manipulation](/test/Business_Logic/Bunni/)



### Reentrancy
- [Qi Dao / Curve Pool - Nov 2022 - (~$156K) - Read Only Reentrancy](/test/Reentrancy/CurvePoolOracle)
- [DFX Finance - Nov 2022 - (~$6MM) - Reentrancy / Side Entrance](/test/Reentrancy/DFXFinance)
- [Fei Protocol, Apr 2022 - (~$80MM) - Cross Function Reentrancy / FlashLoan Attack](/test/Reentrancy/FeiProtocol)
- [Revest Protocol, Mar 2022 - (~$2MM) - ERC1155 Reentrancy / Flashswap Attack](/test/Reentrancy/RevestFinance)
- [Hundred Finance - Mar 2022 - (~$6MM) - Reentrancy / ERC667 Transfer Hook](/test/Reentrancy/HundredFinance)
- [Paraluni - Mar 2022 - (~$1.7MM) - Reentrancy / Arbitrary tokens](/test/Reentrancy/Paraluni)
- [Cream Finance - Aug 2021 - (~$18MM) - Reentrancy / ERC777 Transfer Hook](/test/Reentrancy/CreamFinance)
- [Read Only Reentrancy - N/A - N/A - Read Only Reentrancy](/test/Reentrancy/ReadOnlyReentrancy)

### Bridges
- [Nomad Bridge, Aug 2022 - (~$190MM) - Invalid Root Hash Commitment / Poor Root Validation](/test/Bridges/NomadBridge)
- [Ronin Bridge, Mar 2022 - (~$624MM) - Compromised Keys](/test/Bridges/RoninBridge)
- [Wormhole Bridge, Feb 2022 - (~$10MM, bounty) - Uninitialized bridge](/test/Bridges/Wormhole)
- [PolyNetwork Bridge, Aug 2021 - (~$611MM) - Arbitrary External Calls, Access Control Bypass](/test/Bridges/PolyNetworkBridge)
- [Arbitrum Inbox (REPORTED), Sep 2022 - (400K ETH BUG BOUNTY) - Uninitialized Implementation](/test/Bridges/ArbitrumInbox)


# <h2 align="center"> Contributing </h2>

To contribute, create a new file inside the most appropriate category. Use the `template.txt` file in the `test` folder including the information related to the attack.

Utils that perform flashloans and swaps are provided in `test/utils` to ease the job of reproducing future attacks. Also, modules that provide enhanced features to Foundry are included in the `test/modules` folder. 

The tests should `pass` if the attacker succeeded, for examples: your requires should show that the attacker has more balance after the attack than before.

# <h2 align="center"> Past work and further study </h2>

- [DefiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs) has a similar repository with more exploits and more focus on the test reproductions alone, with no context or further explanations. It is nevertheless great if you only care about the attack reproductions! Go check it out.

## Troubleshooting

The main reason why tests fail is due to failures on the RPC providers we have set up as defaults. Please either:

- Try again
- Change the corresponding provider in the `foundry.toml`

If a reproduction is _still_ failing (ie: it reverts), try to:

- Clean Forge's cache: `forge cache clean`
- Update Foundry: `foundryup`
