import {IERC20} from "../../interfaces/IERC20.sol";

interface IDSToken is IERC20 {
    function pull(address src, uint256 wad) external; // makes a transferFrom
    function mint(address to, uint256 amount) external;
}

interface IMERC20 is IERC20 {
    function mint(address guy, uint256 wad) external;
    function burn(address guy, uint256 wad) external;
    function start() external;
    function stop() external;
}

interface IVat {
    function suck(address u, address v, uint256 rad) external;
    function hope(address usr) external;
}

interface IJoin {
    function exit(address usr, uint256 wad) external;
}

interface IForeignOmnibridge {
    function relayTokens(address token, uint256 _value) external;
}

interface ICurioBridge {
    function lock(bytes32 to, address token, uint256 amount) external;
}

// Interfaces used by the attacker on their contract
interface IDSChief {
    function lock(uint256 wad) external;
    function vote(address[] memory yays) external returns (bytes32);
    function lift(address whom) external;
}

interface IDSPause {
    function plot(address usr, bytes32 tag, bytes memory fax, uint256 eta) external;
    function exec(address usr, bytes32 tag, bytes memory fax, uint256 eta)
        external
        returns (bytes memory out);
}