---
title: Cork Finance
type: Exploit
network: [ethereum]
date: 2025-05-28
loss_usd: 7200000
returned_usd: 0
tags: [business logic, price manipulation, access control]
subcategory: N/A
vulnerable_contracts: "0xccd90f6435dd78c4ecced1fa4db0d7242548a2a9"
tokens_lost:
  - wstETH
attacker_addresses:
  - "0xEA6f30e360192bae715599E15e2F765B49E4da98"
  - "0x6e54115de254805365c2d9c8a2eeb9b52e54668f"
  - "0x9af3dce0813fd7428c47f57a39da2f6dd7c9bb09"
malicious_token: N/A
attack_block: 22580952
reproduction_command: RPC_URL=<rpc_url> forge test --match-contract Exploit_CorkFinance -vvv
attack_txs:
  - "0x14cdf1a643fc94a03140b7581239d1b7603122fbb74a80dd4704dfb336c1dec0"
  - "0xfd89cdd0be468a564dd525b222b728386d7c6780cf7b2f90d2b54493be09f64d"
sources:
  - title: Cork Protocol Post-Mortem
    url: https://www.cork.tech/blog/post-mortem
  - title: Rekt
    url: https://rekt.news/cork-protocol-rekt
  - title: Uniswap V4 Reference Docs
    url: https://docs.uniswap.org/contracts/v4/overview
---

## Step-by-step Overview

The Cork Finance exploit unfolded in two primary, interconnected phases, orchestrated through a series of precise on-chain interactions:

1. Rollover Pricing Manipulation (Cover Token Acquisition):

- The attacker initiated a minimal `swapRaforDs` transaction shortly before the expiry of a targeted `wstETH:weETH` market (specifically 19 minutes prior to expiry).

- This transaction, involving a small amount of `RA` for `DS`, drastically inflated the market's Historical Implied Yield Average (HIYA) due to the exponential sensitivity of the risk premium calculation as time to maturity approached zero.

- Upon rollover, this inflated HIYA value led to the new market's Automated Market Maker (AMM) being initialized with an extremely low price for Cover Tokens (CT) relative to `wstETH`.

- The attacker then acquired a substantial quantity of `CT` from this manipulated AMM with a comparatively negligible amount of `wstETH`.

2. Depeg Swap Extraction (Value Siphoning):

- Following the CT acquisition, the attacker deployed a malicious smart contract (`CorkMaliciousHook` in our reporoduction) designed to function as a malicious callback.

- This malicious contract initiated a new Cork market, registering itself as the `exchangeRateProvider` for this new market's `augDS/wstETH` pair, thereby gaining direct control over its oracle feed and price rate.

- The attacker invoked Uniswap V4's `unlock` function on the `PoolManager`, directing the callback to their malicious smart contract (`CorkMaliciousHook`). Within this callback, `CorkMaliciousHook` invoked the legitimate CorkHook's `beforeSwap` function, leveraging the absence of access control, supplying spoofed transaction parameters.

- These custom-made parameters bypassed insufficient internal validation within the `FlashSwapRouter`'s `corkCall` function.

- This caused the `FlashSwapRouter` to transfer its unsold `augDS` reserves into the attacker's newly created "Exploiter's Proxy Market," where they were used to mint `pDS` and `pCT` directly for the attacker.

- Simultaneously, through AMM pricing manipulation within the `beforeSwap` context, an "over-borrowed" state was created, leading to a refund of excess `pCT` to the attacker's designated address.

- Finally, the accumulated `pCT` and `pDS` were redeemed for `wstETH` from the Peg Stability Module (PSM), effectively draining the Liquidity Vault.

## Detailed Description

The Cork Finance exploit exemplifies a multi-stage attack that abused a combination of economic oracle manipulation and access control bypasses within a complex DeFi protocol architecture. The attacker showed understanding of the interdependencies between Cork's core modules, specifically the `ModuleCore`, `FlashSwapRouter`, and the custom Cork Hook implementation alongside their business logic related to the pricing mechanisms.

### Phase 1: Cover Token Extraction via Rollover Pricing Exploit

This initial vector capitalized on a subtle but critical flaw in Cork Protocol's rollover mechanism, which aimed to ensure liquidity permanence across expiring markets. The Historical Implied Yield Average (HIYA) formula, designed to derive the historical risk premium from `DS` trades, proved vulnerable to manipulation under specific, low-volume conditions.

The HIYA calculation is fundamentally influenced by the risk premium (`rT`), which itself is an inverse function of the time to maturity (`T`). As `T` approaches zero (i.e., market expiry), `rT` exhibits an exponential increase due to the `1/T` term. The attacker exploited this sensitivity by executing a timed, relatively small trade (`initialBorrowAmount = 2e18 DS` with `3.5e15 RA` paid) just 19 minutes prior to the `wstETH:weETH` market's expiry. This single transaction, within a low-volume context, disproportionately skewed the volume-weighted HIYA, inflating it to an astronomical `1,779.7` **quadrillion percent**.

```solidity
// AttackerSC_1.sol (Simplified relevant snippet)
// Guesses made with offchain calculations to inflate the risk premium
// over 1,779.7 quadrillion percent by effectively buying 2.5e18 about-to-expire
// Depeg Swap (DS) tokens
IPSMProxy.OffchainGuess memory offchainGuess;
offchainGuess.initialBorrowAmount = 2e18;
offchainGuess.afterSoldBorrowAmount = 2.55e18; // Corresponds to ~2.5 DS received

// The attacker paid only ~0.003407 wstETH for the requested DS (RA)
flashSwapProxy.swapRaforDs(PAIR_ID_FOR_RATE, 1, 3.5e15, 0, buyParams, offchainGuess);
```

The `offchainGuess` parameters (`initialBorrowAmount`, `afterSoldBorrowAmount`) were pre-calculated by the attacker. While the reproduction utilized values within the same order of magnitude (specifically, `initialBorrowAmount = 2e18` and `afterSoldBorrowAmount = 2.55e18`), the attacker's original exploit employed the precise values of `2035043806577874200` and `2554953564824393000` respectively. These figures were not arbitrary but were precisely calculated to achieve the desired HIYA inflation and optimize the subsequent `swapRaforDs` call, thereby minimizing gas costs and ensuring exploit success by bypassing complex on-chain price calculations. The post-mortem's statement that the attacker "purchased `2.5 DS` approximately 19 minutes prior to expiry" directly correlates with these carefully chosen `offchainGuess` values.

Upon the market's rollover, the protocol's logic utilized this artificially inflated HIYA to initialize the new AMM. This resulted in an exceptionally low post-rollover price for Cover Tokens (CT), effectively rendering them drastically undervalued. The attacker capitalized on this by acquiring over `3,760 CT` with a minuscule amount of `wstETH`, thereby establishing the foundation for the second phase of the attack.

```solidity
// ModuleCore.sol
/**
    * @dev Issues new assets, will auto assign amm fees from the previous issuance
    * for first issuance, separate transaction must be made to set the fees in the AMM
    */
function issueNewDs(Id id, uint256 ammLiquidationDeadline) external whenNotPaused {
    moduleCore.issueNewDs(id, defaultDecayDiscountRateInDays, rolloverPeriodInBlocks, ammLiquidationDeadline);

    _autoAssignFees(id);
    _autoAssignTreasurySplitPercentage(id);
}
```

### Phase 2: Depeg Swap Extraction via Cork Hook and Router Exploit

This phase exploited a series of authorization and validation deficiencies within Cork's integration layers, particularly centered around the custom Cork Hook and its interactions with `FlashSwapRouter`.

The attacker's key strategy was to deploy their own malicious contract, `CorkMaliciousHook`. This contract was designed to serve as the recipient of Uniswap V4 callbacks, specifically by implementing the `unlockCallback` function. This capability allowed it to receive execution control from the Uniswap V4 Pool Manager when `unlock` was called with its address. This design choice enabled the attacker to establish a tightly controlled execution context. From within this callback environment, the `CorkMaliciousHook` then proceeded to interact with and exploit the legitimate `CorkHook`.

A critical step involved `CorkMaliciousHook` initiating a new Cork market by calling `corkConfig.initializeModuleCore`. Crucially, the attacker passed `address(this)` (the `CorkMaliciousHook` contract itself) as the `exchangeRateProvider` parameter for this new market:

```solidity
// CorkMaliciousHook.sol (Relevant snippet)
// 4.8 Initializes a new module core, setting self as the ExchangeRateProvider
corkConfig.initializeModuleCore(address(wstETH), _weETH8DS, 1, 100, address(this));
```

This call effectively registered the `CorkMaliciousHook` as the authoritative oracle for the newly created `augDS/wstETH` pair within Cork's ecosystem. Consequently, any subsequent operations within Cork Protocol that queried the exchange rate for this specific market `ID` would directly invoke the `rate()` functions of the `CorkMaliciousHook` (which are hardcoded to return `0` or `1`), granting the attacker full and unilateral control over the perceived asset pricing. This mechanism, where arbitrary contracts can dictate market-critical parameters without sufficient vetting or robust safeguards, introduces a significant area of risk within the market creation process.

Subsequently, the attacker triggered a Uniswap V4 unlock call on the `PoolManager`, directing the `callback` to `CorkMaliciousHook`'s `unlockCallback`. Within this callback, the malicious hook proceeded to invoke the legitimate CorkHook's `beforeSwap` function (which was public and lacked access control), but with crafted, spoofed `hookData`. This `hookData` contained manipulated parameters for caller, provided, borrowed, and `reserveId`, designed to misrepresent the true state and origin of the transaction.

```solidity
// CorkMaliciousHook.sol (Relevant snippet)
// Callback data passed by the attacker used when UniV4 calls this contract back
struct MaliciousCallbackData {
    address weETH8DS;
    address wstETH5CT;
    bytes32 pairId;
    address wstETH5DS;
}

// ... inside unlockCallback ...

// 4.12 Retrieves necessary information to craft the beforeSwap call
// ...
CallbackData memory flashSwapCallbackData = CallbackData({
    buyDs: true,
    caller: address(this), // Spoofed caller to receive refunds
    borrowed: 0,
    provided: amountToSkim,
    reserveId: newPairIdStorage,
    dsId: 1
});
bytes memory hookData = abi.encode(flashSwapCallbackData);

corkHook.beforeSwap(address(flashSwapProxy), poolKey, swapParams, hookData);
```

Another vulnerability lies in `FlashSwapRouter.CorkCall`'s validation logic. While it correctly asserted that `msg.sender` (the immediate caller, which would be `CorkHook` or its `HookForwarder` after the `beforeSwap` call) was legitimate, it failed to perform sufficient contextual validation on the parameters embedded within the `hookData` itself. This allowed the attacker's spoofed caller address to be passed through, ultimately leading to unauthorized funds being transferred.

```solidity
// CorkHook.sol, logic inside beforeSwap() call.

// call the callback
CorkSwapCallback(sender).CorkCall(sender, hookData, paymentAmount, paymentToken, address(poolManager));
```

```solidity
// FlashSwapRouter.sol, logic inside corkCalll() call.
        {
            // make sure only hook and forwarder can call this function
            assert(msg.sender == address(hook) || msg.sender == address(hook.getForwarder()));
            assert(sender == address(this));
        }
```

This deception caused the `FlashSwapRouter` to:

1. Blindly trust the spoofed provided and borrowed amounts from the `hookData`.

2. Transfer its existing unsold `augDS` reserves (assets that a dispatcher contract should ideally not hold) into the attacker's "Exploiter's Proxy Market" via a `depositPsm` call. This resulted in the minting of `pDS` and `pCT` tokens, which were then transferred to the attacker's control.

3. Simultaneously, by manipulating the AMM pricing during the `beforeSwap` execution, an "over-borrowed" scenario was engineered. This subtle economic imbalance triggered a refund of excess `pCT` directly to the attacker's spoofed caller address, further siphoning legitimate assets.

The culmination of these two attack vectors — the acquisition of highly discounted `CT` and the unauthorized extraction of `DS` — allowed the attacker to possess a significant amount of both `pCT` and `pDS`. These were then redeemed for `3,761 wstETH` from the Peg Stability Module, leading to the complete depletion of the `wstETH:weETH` Liquidity Vault.

## Conclusions beyond the Post-Mortem

### Explicit Confirmation of `exchangeRateProvider` Hijacking:

The direct mechanism for `ExchangeRateProvider` subversion, achieved by registering `CorkMaliciousHook` during `initializeModuleCore`, represents a critical aspect of the exploit. The post-mortem alludes to "bypassing authorization checks," but the precise method of becoming the active oracle for a new market goes beyond a simple access control bypass. This constituted a full oracle hijacking for newly created pairs, fundamentally undermining the integrity of price discovery within those specific markets. The attacker's ability to arbitrarily define the `rate()` function for newly provisioned markets enabled the complete dictation of perceived asset pricing, a powerful primitive for economic manipulation within the protocol.

### Attacker's Rationale: "The Cork Hook is Not the Problem":

The attacker's assertion that `CorkHook` itself was "not the problem" is a key insight into their technical understanding. This statement suggests that the attacker viewed `CorkHook` as functioning correctly according to its role as a Uniswap V4 callback recipient, executing the provided logic. The true flaw resided in Cork Protocol's broader design, specifically the insufficient validation and access control within `CorkHook`'s implementation, but also across Cork's infrastructure as a whole, which collectively failed to properly validate the origin and legitimacy of the `hookData` and its embedded parameters. The problem was not confined to the hook's mechanism, but rather Cork's trusting implementation around that mechanism. Furthermore, the protocol's rollover pricing mechanism is also a significant concern, as it allows for the skewing of a market's risk premium under specific conditions, leading to economic vulnerabilities that can be exploited for substantial gains.

## Possible Mitigations

Based on the identified vulnerabilities and the post-mortem's action plan, several mitigations can be proposed:

1. Access Control:

- **Uniswap V4 Hook Authorization:** Adopt the explicit authorization checks introduced in later Uniswap V4 periphery contracts. This upstream change, missing in Cork's deployed version, would have provided a direct mechanism for developers to verify and whitelist legitimate callers. [Uniswap's V4 sample hooks](https://docs.uniswap.org/contracts/v4/reference/core/test/CustomCurveHook#beforeswap) have an `onlyPoolManager` modifier.

2. Architectural Best Practices and Asset Management:

- **Stateless Dispatchers:** Ensure that dispatcher or routing contracts, such as `FlashSwapRouter`, are designed to be entirely stateless and do not hold significant token balances. Any necessary temporary asset transfers should be handled atomically within a single transaction and reconciled immediately.

- **Segregation of Duties:** Clearly define and enforce the responsibilities of each contract. A contract responsible for routing should not inadvertently become a treasury.

3. Economic Security and Parameter Controls:

- **HIYA Formula Review:** Re-evaluate and potentially re-engineer the HIYA formula, particularly its sensitivity to low-volume trades and close-to-expiry conditions. Consider introducing minimum volume thresholds or time-weighted average price (TWAP) mechanisms for historical data inclusion to mitigate sudden spikes in risk premium calculations.

- **Circuit Breakers:** Implement circuit breakers for large or anomalous trades/movements of assets based on a deviation from a predefined threshold. This could temporarily pause problematic functions or markets.
