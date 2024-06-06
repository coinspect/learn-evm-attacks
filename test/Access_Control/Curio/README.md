# Curio Public Mint
- **Type:** Exploit
- **Network:** Ethereum 
- **Total lost**: ~16MM USD 
- **Category:** Access Control
- **Vulnerable contracts:**
- - [Curio Chief](https://etherscan.io/address/0x579A3244f38112b8AAbefcE0227555C9b6e7aaF0#code)
- - [Curio Pause](https://etherscan.io/address/0x1e692eF9cF786Ed4534d5Ca11EdBa7709602c69f#code)

- **Attack transactions:**
- - [Privilege escalation and mint](https://etherscan.io/tx/0x4ff4028b03c3df468197358b99f5160e5709e7fce3884cc8ce818856d058e106)
  
- **Attacker Addresses**: 
- - Attacker EOA: [0xdaAa6294C47b5743BDafe0613d1926eE27ae8cf5](https://etherscan.io/address/0xdaAa6294C47b5743BDafe0613d1926eE27ae8cf5)
- - Attacker Contract (verified): [0x1E791527AEA32cDDBD7CeB7F04612DB536816545](https://etherscan.io/address/0x1E791527AEA32cDDBD7CeB7F04612DB536816545)
  
- **Attack Block:**:  `19,498,911`  
- **Date:** Mar 23, 2024
- **Reproduce:** `forge test --match-contract=Exploit_Curio -vvv`

## Step-by-step 

## Detailed Description

## Possible mitigations

## Sources and references
- [Curio Tweet](https://twitter.com/curio_invest/status/1771635979192774674)
- [Hacken Tweet](https://x.com/hackenclub/status/1772288824799801401)
- [Rekt Article](https://rekt.news/curio-rekt/)
