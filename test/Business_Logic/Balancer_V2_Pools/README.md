# Balancer V2 Rate Manipulation Attack Reproduction

## Attack Overview
On November 3, 2025, Balancer V2 suffered a $116M+ exploit through rate manipulation of stable pools.

## How The Attack Works

### 1. **Core Vulnerability: Division by Zero Exploitation**

The attacker intentionally triggers `BAL#004` (ZERO_DIVISION) errors in Balancer's math library:

```solidity
// In Balancer's divDown function:
function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
    _require(b != 0, Errors.ZERO_DIVISION); // BAL#004
    return a / b;
}
```

### 2. **The Exploit Technique**

From the decompiled `SC2_decompiled.sol`, we can see the attacker creates a zero denominator:

```solidity
// Lines 221-224: Intentionally creates zero
uint256 denominator = _sub(
    _add(virtualBalance, feeAdjustedWeight),
    _add(virtualBalance, feeAdjustedWeight)  // Same value!
);
// Result: denominator = X - X = 0
```

### 3. **Binary Search Using Reverts as Feedback**

The attacker uses BAL#004 reverts as **feedback in a binary search algorithm** to find optimal manipulation parameters:

1. **Binary Search Algorithm**:
   - Start with a range of possible manipulation values
   - Try midpoint value
   - **If it reverts (BAL#004)**: Value is too high, search lower half
   - **If it succeeds**: Value is too low, search upper half
   - Converge on the exact threshold that maximizes manipulation

2. **The ~30% Revert Rate Explained**:
   - Not random - it's the natural result of binary search convergence
   - Early iterations: Wide search with ~50% reverts
   - Middle iterations: Narrowing down with varying revert rates
   - Late iterations: Oscillating around optimal value (~30% reverts)

3. **Each Iteration**:
   - **Success**: Manipulation progresses, rounding errors introduced
   - **BAL#004 Revert**: Provides feedback AND forces recalculation
   - Both outcomes advance the attack!

4. **Compound Effect**:
   - After 150+ iterations, the attacker has found the optimal manipulation value
   - Pool 1: Rate increases from 1.027 → 20.189 (+1,864%)
   - Pool 2: Rate increases from 1.051 → 3.887 (+270%)

## Files in This Reproduction

- `AttackCoordinator.sol` - Main orchestrator (SC1)
- `BalancerExploitMath.sol` - Mathematical exploit contract (SC2)
- `Balancer_V2_Pools.attack.sol` - Test harness
- `Interfaces.sol` - Required interfaces
- `SC1_decompiled.sol` - Decompiled attacker coordinator
- `SC2_decompiled.sol` - Decompiled exploit math contract

## Key Addresses

**Pools Attacked**:
- osETH/WETH-BPT: `0xDACf5Fa19b1f720111609043ac67A9818262850c`
- wstETH/WETH-BPT: `0x93d199263632a4EF4Bb438F1feB99e57b4b5f0BD`

**Balancer Vault**: `0xBA12222222228d8Ba445958a75a0704d566BF2C8`

**Attack Transactions**:
- Manipulation: `0x6ed07db1a9fe5c0794d44cd36081d6a6df103fab868cdd75d581e3bd23bc9742`
- Extraction: `0xd155207261712c35fa3d472ed1e51bfcd816e616dd4f517fa5959836f5b48569`

## Running the Test

```bash
# Run with verbose output
forge test --match-contract Exploit_Balancer_V2_Pools -vvv

# Run with mainnet fork at specific block
forge test --match-contract Exploit_Balancer_V2_Pools --fork-url $RPC_URL --fork-block-number 21344999 -vvv
```

## Common Issues

### BAL#510 Error
This error occurs when batch swap parameters are invalid. Ensure:
- Token indices are correct
- Pool ID matches the pool
- Assets array includes all tokens involved
- Limits are properly set

### BAL#004 (Expected)
This is the intentional division by zero that's part of the attack. ~30% of manipulation calls should trigger this.

## Mitigation
- Implement checks to prevent division by zero in rate calculations
- Add time-weighted average price (TWAP) mechanisms
- Limit the frequency of rate updates
- Add bounds checking on rate changes