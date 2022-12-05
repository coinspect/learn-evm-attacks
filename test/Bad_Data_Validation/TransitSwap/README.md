# Superfluid 
- **Type:** Exploit
- **Network:** Ethereum / Binance
- **Total lost**: 400K BSC-USD + ~742K USDC (some returned)
- **Category:** Data validation
- **Exploited contracts:**
- - [0xed1afc8c4604958c2f38a3408fa63b32e737c428](https://etherscan.io/address/0xed1afc8c4604958c2f38a3408fa63b32e737c428)
- **Attack transactions:**
- - [0xba75ad7a43e784f51fe777d749fc55ae10f1df2bcb01cde97641613b19acb6ec ](https://etherscan.io/tx/0xba75ad7a43e784f51fe777d749fc55ae10f1df2bcb01cde97641613b19acb6ec)
- - 
[0x181a7882aac0eab1036eedba25bc95a16e10f61b5df2e99d240a16c334b9b189](https://bscscan.com/tx/0x181a7882aac0eab1036eedba25bc95a16e10f61b5df2e99d240a16c334b9b189)
- **Attacker Addresses**: 
- - [0x75F2abA6a44580D7be2C4e42885D4a1917bFFD46](https://etherscan.io/address/0x75F2abA6a44580D7be2C4e42885D4a1917bFFD46)
- **Attack Block:**: 14037237
- **Date:** Oct 02, 2022
- **Reproduce:** `forge test --match-contract Exploit_TransitSwap -vvv`

## Step-by-step 
1. Craft and deploy a contract so that it passes the requirements.
2. Find a victim that had `permit` the contract to use `WETH`.
2. Call `anySwapOutUnderlyingWithPermit` with your malicious contract and the victim's address.

## Detailed Description

Unfortunately, the contracts are not verified, so there is not reliable access to the source code. But looking at the traces, one can see that the contracts had a vulnerable `claimTokens()` method.

This method called `transferFrom` on the specified contract, but did not check the receiver of said funds in the end. The intended usage was to transfer the funds to the Transit Swap Bridge.

## Possible mitigations
- Do not make destinations an input if possible. 


## Sources and references
- -[Superfluid Twitter](https://twitter.com/Superfluid_HQ/status/1491045880107048962) 
- -[Superfluid Writeup](https://medium.com/superfluid-blog/08-02-22-exploit-post-mortem-15ff9c97cdd) 
- -[Rekt Article](https://rekt.news/superfluid-rekt/)
