Overview
On Monday, 07:46 UTC, Hypernative monitoring flagged the first signs of an exploit targeting Balancer V2 Composable Stable Pools. Subsequent analysis confirmed the issue affected Composable Stable Pools across multiple networks, including Ethereum, Base, Avalanche, Gnosis, Berachain, Polygon, Sonic, Arbitrum, and Optimism. The incident was limited to Composable Stable Pools on Balancer V2 and its forks on other chains such as BEX and Beets. Balancer V3 and all other pool types remain unaffected.
Immediate response efforts were initiated in coordination with Balancer contributors, security partners, and whitehat responders, leading to containment of the exploit and the recovery or freezing of a portion of affected assets. A war room coordinated containment, communications, and recovery across networks. CSPv6 Pools were transitioned into Recovery Mode, asset freezes were executed with partners, and whitehat engagement proceeded under the SEAL Safe Harbor framework.
While final impact figures remain under verification, the exploit was significant. A full post-mortem will follow once all technical and legal reviews are complete.
Root Cause (Preliminary)
The V2 Vault supports two types of swaps: simple, and batch. The batch swap allows multiple operations to be combined in a single transaction, which avoids intermediate token transfers and enables significant gas savings.
A key feature of the batch swap is “deferred settlement,” where callers can effectively “flashloan” tokens to perform swaps, as long as everything is paid back at the end. Specifically for composable stable pools, the LP receipt-tokens (BPT) are treated as regular tokens, which allows bypassing the minimum pool supply limit, allowing the liquidity levels in the pool to reach extremely low values.
The exploit originated from the rounding direction in the upscale function affecting EXACT_OUT swaps in Composable Stable Pools. This function rounds down when scaling factors are non-integer values—a condition that occurs when token rates are incorporated into those scaling factors. Attackers were able to exploit the incorrect rounding behavior in combination with the batchSwap functionality to manipulate pool balances and extract value. In many instances, the exploited funds remained within the Vault as internal balances before being withdrawn in subsequent transactions.
Scope of impact:
Composable Stable v5 pools with expired pause windows were primarily affected.
Composable Stable v6 pools were automatically paused by Hypernative and protected.
Balancer v3 and v2 non-stable pool types remain unaffected based on current audits and external review.
Impact
We are prioritizing mitigation and recovery of funds while the investigation remains active. Impact estimates are still being reconciled across chains, pool types, and addresses in coordination with external security teams and whitehat responders.
We maintain a consolidated internal ledger tracking: exploiter flows, whitehat rescues, frozen assets, recovered funds, and protocol/user withdrawals. These entries are under continuous verification.
Final values will be released only after multi-party validation (on-chain trace review, partner confirmations, and reconciliation of block-by-block balances).
Any figures circulating publicly are unconfirmed and should not be treated as official.
A verified accounting of affected pools and recovered assets, including methodology and transaction references, will be published in the final post-mortem.
