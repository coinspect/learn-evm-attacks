// roles.sol - roled based authentication

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

import "./auth.sol";

contract DSRoles is DSAuth, DSAuthority {
    mapping(address => bool) _root_users;
    mapping(address => bytes32) _user_roles;
    mapping(address => mapping(bytes4 => bytes32)) _capability_roles;
    mapping(address => mapping(bytes4 => bool)) _public_capabilities;

    function getUserRoles(address who) public view returns (bytes32) {
        return _user_roles[who];
    }

    function getCapabilityRoles(address code, bytes4 sig) public view returns (bytes32) {
        return _capability_roles[code][sig];
    }

    function isUserRoot(address who) public view virtual returns (bool) {
        return _root_users[who];
    }

    function isCapabilityPublic(address code, bytes4 sig) public view returns (bool) {
        return _public_capabilities[code][sig];
    }

    function hasUserRole(address who, uint8 role) public view returns (bool) {
        bytes32 roles = getUserRoles(who);
        bytes32 shifted = bytes32(uint256(uint256(2) ** uint256(role)));
        return bytes32(0) != roles & shifted;
    }

    function canCall(address caller, address code, bytes4 sig) public view returns (bool) {
        if (isUserRoot(caller) || isCapabilityPublic(code, sig)) {
            return true;
        } else {
            bytes32 has_roles = getUserRoles(caller);
            bytes32 needs_one_of = getCapabilityRoles(code, sig);
            return bytes32(0) != has_roles & needs_one_of;
        }
    }

    function BITNOT(bytes32 input) internal pure returns (bytes32 output) {
        return (input ^ bytes32(type(uint256).max));
    }

    function setRootUser(address who, bool enabled) public virtual auth {
        _root_users[who] = enabled;
    }

    function setUserRole(address who, uint8 role, bool enabled) public auth {
        bytes32 last_roles = _user_roles[who];
        bytes32 shifted = bytes32(uint256(uint256(2) ** uint256(role)));
        if (enabled) {
            _user_roles[who] = last_roles | shifted;
        } else {
            _user_roles[who] = last_roles & BITNOT(shifted);
        }
    }

    function setPublicCapability(address code, bytes4 sig, bool enabled) public auth {
        _public_capabilities[code][sig] = enabled;
    }

    function setRoleCapability(uint8 role, address code, bytes4 sig, bool enabled) public auth {
        bytes32 last_roles = _capability_roles[code][sig];
        bytes32 shifted = bytes32(uint256(uint256(2) ** uint256(role)));
        if (enabled) {
            _capability_roles[code][sig] = last_roles | shifted;
        } else {
            _capability_roles[code][sig] = last_roles & BITNOT(shifted);
        }
    }
}
