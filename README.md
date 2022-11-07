# <h1 align="center"> Reproduced Exploits Library </h1>
A library with previously exploited vulnerabilities, categorized by type (common denominator of each exploit).

Each exploit can be found under the test folder.

## Index
### [How to Install, Compile and Run](https://github.com/coinspect/prev-exploit-library#-hardhat-x-foundry-template-)

### Bad Input Validation
- [Olympus DAO Bond, Oct 2022 - ($300,000)](https://github.com/coinspect/prev-exploit-library/blob/master/test/Bad_Input_Validation/Bond_OlympusDAO.attack.sol)
- [Multichain a.k.a AnySwap, Jan 2022 - ($960,000)](https://github.com/coinspect/prev-exploit-library/blob/master/test/Bad_Input_Validation/Multichain_Permit.attack.sol)

# <h2 align="center"> How to Install, Compile and Run </h2>

**Template repository for getting started quickly with Hardhat and Foundry in one project**

![Github Actions](https://github.com/devanonon/hardhat-foundry-template/workflows/test/badge.svg)

### Getting Started

 * Use Foundry: 
```bash
forge install
forge test
```

 * Use Hardhat:
```bash
npm install
npx hardhat test
```

### Features

 * Write / run tests with either Hardhat or Foundry:
```bash
forge test
# or
npx hardhat test
```

 * Use Hardhat's task framework
```bash
npx hardhat example
```

 * Install libraries with Foundry which work with Hardhat.
```bash
forge install rari-capital/solmate # Already in this repo, just an example
```

### Notes

Whenever you install new libraries using Foundry, make sure to update your `remappings.txt` file by running `forge remappings > remappings.txt`. This is required because we use `hardhat-preprocessor` and the `remappings.txt` file to allow Hardhat to resolve libraries you install with Foundry.
