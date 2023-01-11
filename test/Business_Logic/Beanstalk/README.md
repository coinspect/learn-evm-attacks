# Beanstalk
- **Type:** Exploit
- **Network:** Ethereum 
- **Total lost:** ~$181MM USD (in multiple tokens, stolen a bit less than a half in WETH)
- **Category:** Governance can be exploited during flashloan
- **Vulnerable contracts:**
- - [0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5](https://etherscan.io/address/0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5)
- **Attack transactions:**
- - [0x3cb358d40647e178ee5be25c2e16726b90ff2c17d34b64e013d8cf1c2c358967](https://etherscan.io/tx/0x3cb358d40647e178ee5be25c2e16726b90ff2c17d34b64e013d8cf1c2c358967) Proposal
- - [0xcd314668aaa9bbfebaf1a0bd2b6553d01dd58899c508d4729fa7311dc5d33ad7](https://etherscan.io/tx/0xcd314668aaa9bbfebaf1a0bd2b6553d01dd58899c508d4729fa7311dc5d33ad7) Execution
- **Attacker Addresses**: 
- - EOA: [0x1c5dcdd006ea78a7e4783f9e6021c32935a10fb4](https://etherscan.io/address/0x1c5dcdd006ea78a7e4783f9e6021c32935a10fb4)
- - Contract: [0x79224bc0bf70ec34f0ef56ed8251619499a59def](https://etherscan.io/address/0x79224bc0bf70ec34f0ef56ed8251619499a59def)
- **Attack Block:**: 14602790
- **Date:** Apr 17, 2022
- **Reproduce:** `forge test --match-contract Exploit_Beanstalk`

The attack exploit an issue in the governance contract.

The governance has the ability to immediatelly execute an `emergencyProposal` if enough votes are gathered for it (2/3 of voting power, considered a supermajority). This characteristic combined with flash loans created the scenario for this exploit.

Vulnerable code:
```solidity
    function emergencyCommit(uint32 bip) external {
        require(isNominated(bip), "Governance: Not nominated.");
        require(
            block.timestamp >= timestamp(bip).add(C.getGovernanceEmergencyPeriod()),
            "Governance: Too early.");
        require(isActive(bip), "Governance: Ended.");
        require(
            bipVotePercent(bip).greaterThanOrEqualTo(C.getGovernanceEmergencyThreshold()),
            "Governance: Must have super majority."
        );
        _execute(msg.sender, bip, false, true); 
    }

    function _execute(address account, uint32 bip, bool ended, bool cut) private {
        if (!ended) endBip(bip);
        s.g.bips[bip].executed = true;

        if (cut) cutBip(bip);
        pauseOrUnpauseBip(bip);

        incentivize(account, ended, bip, C.getCommitIncentive());
        emit Commit(account, bip);
    }

    function incentivize(address account, bool compound, uint32 bipId, uint256 amount) private {
        if (compound) amount = LibIncentive.fracExp(amount, 100, incentiveTime(bipId), 2);
        IBean(s.c.bean).mint(account, amount);
        emit Incentivization(account, amount);
    }
```
The `emergencyCommit` function execute the proposal if `getGovernanceEmergencyThreshold` is reached, which is 2/3 of the votes.

The attackers first submit porpsals bip18 and bip19. The first one being the real exploit while the later a probable disguease, where it donates funds to the Ukraine foundation.

After 1 day, the exploit was produced using flashlons from aave, uniswap and sushi. The attackers flashloan funds in USDT, USDC, DAI, BEAN and LUSD. Using these funds the swap the values for BEAN tokens and call `emergencyCommit`. Once the delegateCall is produced from the beanstalk silo contract, they send funds in multiple tokens to the `0x79224bc0bf70ec34f0ef56ed8251619499a59def` address hold by the attacker. These funds are then used to pay the flashloans and are swapped into WETH which is later deposited in Tornado.

The attacker was cautious.
1. They disuised the attack by submitting an incomplete proposal and sending the relevant data during the exploit
2. They added a simple proposal sending funds to a foundation to look well intended
3. They called multiple flashloans so funds would be enough even when only one would've been enough

Point 3. added some extra cost on the attack which could've been saved if checking for voting power before voting.

This vulnerability is exploited here with a few difference from the original exploit: no disguise is performed, everything uses the same contract and funds are not exchanged for WETH.

Further readings
https://rekt.news/beanstalk-rekt/
https://medium.com/coinmonks/beanstalkfarms-attack-event-analysis-6980482a9b00

Other exploits
https://github.com/SunWeb3Sec/DeFiHackLabs/blob/main/src/test/Beanstalk_exp.sol
https://github.com/JIAMING-LI/BeanstalkProtocolExploit/blob/master/contracts/Exploit.sol
