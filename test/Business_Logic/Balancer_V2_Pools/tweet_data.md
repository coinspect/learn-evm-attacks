.
@Balancer
 and several forked projects were attacked a few hours ago, resulting in losses exceeding $120M across multiple chains. This was a highly sophisticated exploit. Our initial analysis suggests the root cause was an invariant manipulation that distorted the BPT price calculation, allowing the attacker to profit from a specific stable pool through a single batch swap.

Take an attack TX on Arbitrum as an example, the batchSwap operation can be broken down into three phases:
1. The attacker swaps BPT for underlying assets to precisely adjust the balance of one token (cbETH) to the edge of a rounding boundary (amount = 9). This sets up the conditions for precision loss in the next step.
2. The attacker then swaps between another underlying (wstETH) and cbETH using a crafted amount (= 8). Due to rounding down when scaling token amounts, the computed Δx becomes slightly smaller (8.918 to 8), leading to an underestimated Δy and thus a smaller invariant (D from Curve’s StableSwap model). Since BPT price = D / totalSupply, the BPT price becomes artificially deflated.
3. The attacker reverse-swaps the underlying assets back into BPT, restoring balance while profiting from the deflated BPT price.


source: https://x.com/Phalcon_xyz/status/1985302779263643915