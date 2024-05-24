import {IERC20} from "../../interfaces/IERC20.sol";

interface IDSToken is IERC20 {
    function pull(address src, uint256 wad) external; // makes a transferFrom
}

interface IForeignOmnibridge {
    function relayTokens(address token, uint256 _value) external;
}

interface ICurioBridge {
    function lock(bytes32 to, address token, uint256 amount) external;
}
