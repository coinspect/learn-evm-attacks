// chief.sol - select an authority by consensus

// Copyright (C) 2017  DappHub, LLC

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity >=0.8.23;

import "./token.sol";
import "./roles.sol";
import "./thing.sol";

// The right way to use this contract is probably to mix it with some kind
// of `DSAuthority`, like with `ds-roles`.
//   SEE DSChief
contract DSChiefApprovals is DSThing {
    mapping(bytes32 => address[]) public slates;
    mapping(address => bytes32) public votes;
    mapping(address => uint256) public approvals;
    mapping(address => uint256) public deposits;
    DSToken public GOV; // voting token that gets locked up
    DSToken public IOU; // non-voting representation of a token, for e.g. secondary voting mechanisms
    address public hat; // the chieftain's hat

    uint256 public MAX_YAYS;

    mapping(address => uint256) public last;

    bool public live;

    uint256 constant LAUNCH_THRESHOLD = 80_000 * 10 ** 18; // 80K MKR launch threshold

    event Etch(bytes32 indexed slate);

    // IOU constructed outside this contract reduces deployment costs significantly
    // lock/free/vote are quite sensitive to token invariants. Caution is advised.
    constructor(DSToken GOV_, DSToken IOU_, uint256 MAX_YAYS_) public {
        GOV = GOV_;
        IOU = IOU_;
        MAX_YAYS = MAX_YAYS_;
    }

    function launch() public note {
        require(!live);
        require(hat == address(0) && approvals[address(0)] >= LAUNCH_THRESHOLD);
        live = true;
    }

    function lock(uint256 wad) public note {
        last[msg.sender] = block.number;
        GOV.pull(msg.sender, wad);
        IOU.mint(msg.sender, wad);
        deposits[msg.sender] = add(deposits[msg.sender], wad);
        addWeight(wad, votes[msg.sender]);
    }

    function free(uint256 wad) public note {
        require(block.number > last[msg.sender]);
        deposits[msg.sender] = sub(deposits[msg.sender], wad);
        subWeight(wad, votes[msg.sender]);
        IOU.burn(msg.sender, wad);
        GOV.push(msg.sender, wad);
    }

    function etch(address[] memory yays) public note returns (bytes32 slate) {
        require(yays.length <= MAX_YAYS);
        requireByteOrderedSet(yays);

        bytes32 hash = keccak256(abi.encodePacked(yays));
        slates[hash] = yays;
        emit Etch(hash);
        return hash;
    }

    function vote(address[] memory yays) public returns (bytes32) 
    // note  both sub-calls note
    {
        bytes32 slate = etch(yays);
        vote(slate);
        return slate;
    }

    function vote(bytes32 slate) public note {
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

    // like `drop`/`swap` except simply "elect this address if it is higher than current hat"
    function lift(address whom) public note {
        require(approvals[whom] > approvals[hat]);
        hat = whom;
    }

    function addWeight(uint256 weight, bytes32 slate) internal {
        address[] storage yays = slates[slate];
        for (uint256 i = 0; i < yays.length; i++) {
            approvals[yays[i]] = add(approvals[yays[i]], weight);
        }
    }

    function subWeight(uint256 weight, bytes32 slate) internal {
        address[] storage yays = slates[slate];
        for (uint256 i = 0; i < yays.length; i++) {
            approvals[yays[i]] = sub(approvals[yays[i]], weight);
        }
    }

    // Throws unless the array of addresses is a ordered set.
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

// `hat` address is unique root user (has every role) and the
// unique owner of role 0 (typically 'sys' or 'internal')
contract DSChief is DSRoles, DSChiefApprovals {
    constructor(DSToken GOV, DSToken IOU, uint256 MAX_YAYS) public DSChiefApprovals(GOV, IOU, MAX_YAYS) {
        authority = this;
        owner = address(0);
    }

    function setOwner(address owner_) public override {
        owner_;
        revert();
    }

    function setAuthority(DSAuthority authority_) public override {
        authority_;
        revert();
    }

    function isUserRoot(address who) public view override returns (bool) {
        return (live && who == hat);
    }

    function setRootUser(address who, bool enabled) public override {
        who;
        enabled;
        revert();
    }
}

contract DSChiefFab {
    function newChief(DSToken gov, uint256 MAX_YAYS) public returns (DSChief chief) {
        DSToken iou = new DSToken("IOU");
        chief = new DSChief(gov, iou, MAX_YAYS);
        iou.setOwner(address(chief));
    }
}
