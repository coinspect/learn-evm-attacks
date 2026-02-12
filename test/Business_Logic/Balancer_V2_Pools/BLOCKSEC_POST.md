This was a highly sophisticated attack. Our investigation reveals that the root cause was price manipulation resulting from precision loss in the invariant calculation, which in turn distorted the BPT (Balancer Pool Token) price computation. This invariant manipulation allowed the attacker to profit from a specific stable pool through a single batch swap. While some researchers have provided insightful analyses, certain interpretations are misleading, and the root cause and attack process have not yet been fully clarified. This blog aims to present a comprehensive and accurate technical analysis of the incident.
Key Takeaways (TL;DR)
Root cause: rounding inconsistency and precision loss
The upscaling operation uses unidirectional rounding (rounding down), while the downscaling operation uses bidirectional rounding (rounding up and down).
This inconsistency creates precision loss that, when exploited through a carefully crafted swap path, violates the standard principle that rounding should always favor the protocol.
Exploit execution
The attacker deliberately crafted parameters, including the number of iterations and input values, to maximize the effect of the precision loss.
The attacker used a two-stage approach to evade detection: first executing the core exploit within a single transaction without immediate profit, then realizing profits by withdrawing assets in a separate transaction.
Operational impact and amplification
The protocol could not be paused due to certain constraints [3]. This inability to halt operations exacerbated the exploit's impact and enabled numerous subsequent or copycat attacks.
In the following sections, we will first provide key background information about Balancer V2, followed by an in-depth analysis of the identified issues and the associated attack.
0x1 Background
1. Balancer V2's Composable Stable Pool
The affected component in this attack was the Composable Stable Pool [4] of the Balancer V2 protocol. These pools are designed for assets that are expected to maintain near 1:1 parity (or trade at a known exchange rate) and allow large swaps with minimal price impact, thereby significantly improving capital efficiency between like-kind or correlated assets. Each pool has its own Balancer Pool Token (BPT), which represents the liquidity provider's share of the pool, along with the corresponding underlying assets.
This pool adopts Stable Math (based on Curve’s StableSwap model), where the invariant D represents the pool’s virtual total value.
The BPT price can be approximated as:
From the above formula, it can be seen that if D can be made smaller on paper (even without any actual loss of funds), the BPT price will appear cheaper.
2. batchSwap() and onSwap()
Balancer V2 provides the batchSwap() function, which enables multi-hop swaps within the Vault [5]. There are two swap types determined by a parameter passed to this function:
GIVEN_IN ("Given In"): the caller specifies the exact amount of the input token, and the pool calculates the corresponding output amount.
GIVEN_OUT ("Given Out"): the caller specifies the desired output amount, and the pool computes the required input amount.
Typically, a batchSwap() consists of multiple token-to-token swaps executed via the onSwap() function. The following outlines the execution path when a SwapRequest is assigned a GIVEN_OUT swap type (note that ComposableStablePool inherits from BaseGeneralPool):
The following shows the calculation of amount_in for the GIVEN_OUT swap type, which involves the invariant D.
// inGivenOut token x for y - polynomial equation to solve
// ax = amount in to calculate                                     
// bx = balance token in                                                                 
// x = bx + ax (finalBalanceIn)                                                                
// D = invariant
// A = amplification coefficient
// n = number of tokens
// S = sum of final balances but x                                                             
// P = product of final balances but x                                                         

                   D                     D^(n+1)  
  x^2 + ( S - ----------  - D) * x -  ------------- = 0         
               (A * n^n)               A * n^2n * P             
3. Scaling and Rounding
To normalize the calculations across different token balances, Balancer performs the following two operations:
Upscaling: Scale balances and amounts up to a unified internal precision before performing calculations.
Downscaling: Convert the results back to their native precision, applying directional rounding (for example, input amounts are usually rounded up to ensure the pool does not undercharge, while output amounts are often rounded down).
Obviously, upscaling and downscaling are theoretically paired operations—multiplication and division, respectively. However, an inconsistency exists in the implementation of these two operations. Specifically, the downscaling operation has two variants or directions: divUp and divDown. In contrast, the upscaling operation has only one direction, namely mulDown.
The reason for this inconsistency is unclear. According to the comment in the _upscale() function, the developers consider the impact of rounding in a single direction to be minimal.
// Upscale rounding wouldn't necessarily always go in the same direction: in a swap for example the balance of
// token in should be rounded up, and that of token out rounded down. This is the only place where we round in
// the same direction for all amounts, as the impact of this rounding is expected to be minimal (and there's no
// rounding error unless `_scalingFactor()` is overriden).
0x2 Vulnerability Analysis
The underlying issue arises from the rounding-down operation performed during upscaling in the BaseGeneralPool._swapGivenOut() function. In particular, _swapGivenOut() incorrectly rounds down swapRequest.amount through the _upscale() function. The resulting rounded value is subsequently used as amountOut when calculating amountIn via _onSwapGivenOut(). This behavior contradicts the standard practice that rounding should be applied in a manner that benefits the protocol.
Therefore, for a given pool (wstETH/rETH/cbETH), the computed amountIn underestimates the actual required input. This allows a user to exchange a smaller quantity of one underlying asset (e.g., wstETH) for another (e.g., cbETH), thereby decreasing the invariant D as a result of reduced effective liquidity. Consequently, the price of the corresponding BPT (wstETH/rETH/cbETH) becomes deflated, since BPT price = D / totalSupply.
0x3 Attack Analysis
The attacker executed a two-stage attack, likely to minimize detection risk:
In the first stage, the core exploit was performed within a single transaction, yielding no immediate profit.
In the second stage, the attacker realized profits by withdrawing assets in a separate transaction.
The first stage can be further divided into two phases: parameter calculation and batch swap. Below, we illustrate these phases using an example attack transaction (TX) on Arbitrum (https://app.blocksec.com/explorer/tx/arbitrum/0x7da32ebc615d0f29a24cacf9d18254bea3a2c730084c690ee40238b1d8b55773).
The Parameter Calculation Phase
In this phase, the attacker combined off-chain calculations with on-chain simulations to precisely tune each hop's parameters in the next (batch swap) phase, based on the current state of the Composable Stable Pool (including scaling factors, amplification coefficient, BPT rate, swap fees, and other parameters). Interestingly, the attacker also deployed an auxiliary contract to assist with these calculations, which may have been intended to reduce exposure to front-running.
At the start, the attacker collects basic information about the target pool, including each token’s scaling factors, the amplification parameter, the BPT rate, and the swap fee percentage. They then compute a key value called trickAmt, which is the manipulated amount of the target token used to induce precision loss.
Denoting the target token’s scaling factor as sF, the calculation is:
To determine the parameters used in step 2 of the next (batch swap) phase, the attacker made subsequent simulation calls to the 0x524c9e20 function of the auxiliary contract with the following calldata:
uint256[] balances; // Balances of pool tokens (excluding BPT)
uint256[] scalingFactors; // Scaling factors for each pool token
uint tokenIn; // Index of the input token for this hop's simulation
uint tokenOut; // Index of the output token for this hop's simulation
uint256 amountOut; // Desired output token amount
uint256 amp; // Amplification parameter of the pool
uint256 fee; // Pool swap fee percentage
And the return data is:
uint256[] balances; // Pool token balances (excluding BPT) after the swap
Specifically, the initial balance and the number of iteration loops were computed off-chain and passed as parameters to the attacker's contract (reported as 100,000,000,000 and 25, respectively). Each iteration performs three swaps:
Swap 1: Push the target token’s amount to trickAmt + 1, assuming the swap direction is 0 → 1.
Swap 2: Continue swapping out the target token with trickAmt, which triggers rounding down in the _upscale() invocation.
Swap 3: Execute a swap-back operation (1 → 0), where the amount to be swapped is derived from the current token balance in the pool by truncating the two most significant decimal digits, that is, rounding down to the nearest multiple of 10^{d-2}, whererd is the number of decimal digits. For example, 324,816 -> 320,000.
Note that this step may occasionally fail due to the Newton–Raphson method used in the StableMath calculation. To mitigate this, the attacker implements two retry attempts, each using a 9/10 fallback of the original value.
The attacker’s auxiliary contract is derived from Balancer V2's StableMath library, as evidenced by the inclusion of the "BAL"-style custom error messages.
The Batch Swap Phase
Then, the batchSwap() operation can be broken down into three steps:
Step 1: The attacker swaps BPT (wstETH/rETH/cbETH) for underlying assets to precisely adjust the balance of one token (cbETH) to the edge of a rounding boundary (amount = 9). This sets up the conditions for precision loss in the next step.
Step 2: The attacker then swaps between another underlying (wstETH) and cbETH using a crafted amount (= 8). Due to rounding down when scaling token amounts, the computed Δx becomes slightly smaller (8.918 to 8), leading to an underestimated Δy and thus a smaller invariant (D from Curve’s StableSwap model). Since BPT price = D / totalSupply, the BPT price becomes artificially deflated.
Step 3: The attacker reverse-swaps the underlying assets back into BPT, restoring balance while profiting from the deflated BPT price.
0x4: Attacks and Losses
We have summarized the attacks and their corresponding losses in the table below, with total losses exceeding $125 million.
0x5 Conclusion
This incident involved a series of attack transactions targeting the Balancer V2 protocol and its forked projects, resulting in significant financial losses. Following the initial attack, numerous subsequent and copycat transactions were observed across multiple chains. This event highlights several critical lessons for the design and security of DeFi protocols:
Rounding Behavior and Precision Loss: The unidirectional rounding (rounding down) used in the upscaling operation differs from the bidirectional rounding (rounding up and down) used in the downscaling operation. To prevent similar vulnerabilities, protocols should employ higher-precision arithmetic and implement robust validation checks. It is essential to uphold the standard principle that rounding should always favor the protocol.
Evolution of Exploitation: The attacker carried out a sophisticated two-stage exploit designed to evade detection. In the first stage, the attacker executed the core exploit within a single transaction without immediate profit. In the second stage, the attacker realized profits by withdrawing assets in a separate transaction. This incident once again highlights the ongoing arms race between security researchers and attackers.
Operational Awareness and Threat Response: This incident underscores the importance of timely alerts regarding initialization and operational status, as well as proactive threat detection and prevention mechanisms to mitigate potential losses from ongoing or copycat attacks. 
While maintaining operational and business continuity, industry participants can leverage BlockSec Phalcon as the last line of defense to safeguard their assets. The BlockSec expert team stands ready to conduct a comprehensive security assessment for your project.
