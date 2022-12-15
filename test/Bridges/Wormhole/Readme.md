# Wormhole Bridge
- **Type:** Report
- **Network:** Ethereum 
- **Total lost**: 10M USD (bounty price)
- **Category:** Reinitialization
- **Vulnerable contracts:**
- - Vulnerable implementation: [0x736d2a394f7810c17b3c6fed017d5bc7d60c077d](https://etherscan.io/address/0x736d2a394f7810c17b3c6fed017d5bc7d60c077d)
- - Proxy: [0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B](https://etherscan.io/address/0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B)
- **Attack transactions:**
- - None
- **Attacker Addresses**: 
- - None
- **Attack Block:**: -
- **Date:** Feb 24, 2022 (report and fix)
- **Reproduce:** `forge test --match-contract Report_Wormhole -vvv`

## Step-by-step 
1. Craft an evil `_bridge` contract
2. Call `initialize` on the implementation contract to set the attacker controlled `guardian`
3. Call `submitContractUpgrade` on the implementation contract, providing attacker controlled signature and payloads, setting the `_bridge` to be your malicious contract

## Detailed Description

Wormhole is a bridge that enables interoperability between blockchains such as Ethereum, Terra, and Binance Smart Chain (BSC).

The bridge implements a Proxy Standard to be able to upgrade its contract implementation logic.

To do this, it takes a reference to the bridge address in its `initialize`. As hinted by this method, the whole contract is behind an [Universal Upgradable Proxy](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable).

The problem can be found in the initialization of the implementation contract. While the upgrade procedure (`submitContractUpgrade`) is protected by a multi-sig held by its Guardians, these signatures are set by the `initialize` method. This procedure is normally protected by a lock, ensuring that this method can only be called once. However, the Wormhole proxy was Uninitialized. 

``` solidity
    function initialize(address[] memory initialGuardians, uint16 chainId, uint16 governanceChainId, bytes32 governanceContract) initializer public {
        require(initialGuardians.length > 0, "no guardians specified");

        Structs.GuardianSet memory initialGuardianSet = Structs.GuardianSet({
            keys : initialGuardians,
            expirationTime : 0
        });

        storeGuardianSet(initialGuardianSet, 0);
        // initial guardian set index is 0, which is the default value of the storage slot anyways

        setChainId(chainId);

        setGovernanceChainId(governanceChainId);
        setGovernanceContract(governanceContract);
    }

    modifier initializer() {
        address implementation = ERC1967Upgrade._getImplementation();

        require(
            !isInitialized(implementation),
            "already initialized"
        );

        setInitialized(implementation);

        _;
    }
```
This results in the contract being marked as not-initialized in the saved state. At this point anyone can call `initialize`, providing their own set of authorized guardians.
Next, an attacker can call `submitContractUpgrade` providing signatures and a contract of choice to replace the logic implementation.

```
    function submitContractUpgrade(bytes memory _vm) public {
        Structs.VM memory vm = parseVM(_vm);

        (bool isValid, string memory reason) = verifyGovernanceVM(vm);
        require(isValid, reason);

        GovernanceStructs.ContractUpgrade memory upgrade = parseContractUpgrade(vm.payload);

        require(upgrade.module == module, "Invalid Module");
        require(upgrade.chain == chainId(), "Invalid Chain");

        setGovernanceActionConsumed(vm.hash);

        upgradeImplementation(upgrade.newContract);
    }
```
```
    function upgradeImplementation(address newImplementation) internal {
        address currentImplementation = _getImplementation();

        _upgradeTo(newImplementation);

        // Call initialize function of the new implementation
        (bool success, bytes memory reason) = newImplementation.delegatecall(abi.encodeWithSignature("initialize()"));

        require(success, string(reason));

        emit ContractUpgraded(currentImplementation, newImplementation);
    }
```

An attacker could have easily exploit this by initializing the proxy, then submitting a contract to upgrade. An evil contract would brick the proxy, locking Wormhole funds for ever.

## Possible mitigations
- Be careful when implementing proxy upgradability
- Make sure to implement secure authorization schemes
- Test deploy conditions, like `contract should be initialized` and `should not be able to reinitialize contract`

## Diagrams and graphs

### Class

![class](wormhole.png)

## Sources and references
- [Writeup](https://medium.com/immunefi/wormhole-uninitialized-proxy-bugfix-review-90250c41a43a)


