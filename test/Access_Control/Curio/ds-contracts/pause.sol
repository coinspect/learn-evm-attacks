pragma solidity ^0.8.24;

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
