// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "forge-std/test.sol";
interface IERC20Local {
    function name() external view returns(string memory);
    function decimals() external view returns(uint8);
    function balanceOf(address account) external view returns (uint256);
}

library Strings {
    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

        function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10**64) {
                value /= 10**64;
                result += 64;
            }
            if (value >= 10**32) {
                value /= 10**32;
                result += 32;
            }
            if (value >= 10**16) {
                value /= 10**16;
                result += 16;
            }
            if (value >= 10**8) {
                value /= 10**8;
                result += 8;
            }
            if (value >= 10**4) {
                value /= 10**4;
                result += 4;
            }
            if (value >= 10**2) {
                value /= 10**2;
                result += 2;
            }
            if (value >= 10**1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), _SYMBOLS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }
}

contract TokenBalanceTracker {
    using Strings for uint256;

    mapping(address => mapping (address => uint256)) public balanceTracker; // tracks: user => (token => amount).
    address[] public trackedTokens;

    // Will look something like this. For simplicity, WETH could be the last token.
    // address[] tokens = [
    //     0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
    //     0x677ddbd918637E5F2c79e164D402454dE7dA8619, // VUSD
    //     0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
    //     0x86ed939B500E121C0C5f493F399084Db596dAd20, // SPC
    //     0x1b40183EFB4Dd766f11bDa7A7c3AD8982e998421, // VSP
    //     0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2  // WETH (used only here for balance tracking) 
    // ];

    struct BalanceDeltaReturn {
        string sign;
        uint256 value;
    }

    function addTokensToTracker(address[] memory _tokens) public {
        uint256 tokensLength = _tokens.length;
        for(uint256 i = 0; i < tokensLength; i++){
            trackedTokens.push(_tokens[i]);
        }
    }

    function addTokenToTracker(address _token) public {
        trackedTokens.push(_token);
    }

    function logBalances(address _from) public {
        (BalanceDeltaReturn memory nativeTokenDelta, BalanceDeltaReturn[] memory tokensDelta) = calculateBalanceDelta(_from);

        // NATIVE TOKENS HANDLING (12-9)
        if(nativeTokenDelta.value == 0) {
            console.log('Native Tokens: %s', toStringWithDecimals(_from.balance, 18));
        } else {
            console.log('Native Tokens: %s (%s%s)', toStringWithDecimals(_from.balance, 18), nativeTokenDelta.sign, toStringWithDecimals(nativeTokenDelta.value, 18));
        }

        // Other tokens
        uint256 tokensLength = trackedTokens.length;
        if(tokensLength > 0){
            for(uint i = 0; i < tokensLength; i++){
                IERC20Local curToken = IERC20Local(trackedTokens[i]);
                if(tokensDelta[i].value == 0) {
                    console.log('%s: %s', curToken.name(), toStringWithDecimals(curToken.balanceOf(_from), curToken.decimals()));
                } else {
                    string memory deltaAndSign = string.concat(tokensDelta[i].sign, toStringWithDecimals(tokensDelta[i].value, curToken.decimals()));
                    console.log('%s: %s (%s)',  curToken.name(), toStringWithDecimals(curToken.balanceOf(_from), curToken.decimals()), deltaAndSign);
                }
            }
        }

        updateBalanceTracker(_from);
        console.log('\n');
    }

    function toStringWithDecimals(uint256 _number, uint8 decimals) internal pure returns(string memory){
        uint256 integerToPrint = _number / (10**decimals);
        uint256 decimalsToPrint = _number - (_number / (10**decimals)) * (10**decimals);
        return string.concat(integerToPrint.toString(), '.', decimalsToPrint.toString());
    }

    function updateBalanceTracker(address _user) internal {
        balanceTracker[_user][address(0)] = _user.balance;

        uint256 tokensLength = trackedTokens.length;
        if(tokensLength == 0) return;

        for(uint i = 0; i < tokensLength; i++){
            IERC20Local curToken = IERC20Local(trackedTokens[i]);
            balanceTracker[_user][trackedTokens[i]] = curToken.balanceOf(_user);
        }        
    }

    function getBalanceTrackers(address _user) public view returns(uint256 nativeBalance, uint256[] memory tokenBalances){
        nativeBalance = balanceTracker[_user][address(0)];
        
        uint256 tokensLength = trackedTokens.length;
        if(tokensLength > 0) {
            uint256[] memory memBalances = new uint256[](tokensLength);
            for(uint i = 0; i < tokensLength; i++){
                memBalances[i] = balanceTracker[_user][trackedTokens[i]];
            } 
            tokenBalances = memBalances;    
        }
    }

    function calculateBalanceDelta(address _user) internal view returns(BalanceDeltaReturn memory nativeDelta, BalanceDeltaReturn[] memory tokenDeltas){
        (uint256 prevNativeBalance, uint256[] memory prevTokenBalance) = getBalanceTrackers(_user);

        nativeDelta.value = _user.balance > prevNativeBalance ? (_user.balance - prevNativeBalance) : (prevNativeBalance - _user.balance);
        nativeDelta.sign = _user.balance > prevNativeBalance ? ('+') : ('-');

        uint256 tokensLength = trackedTokens.length;
        if(tokensLength > 0) {
            BalanceDeltaReturn[] memory memDeltas = new BalanceDeltaReturn[](tokensLength);
            for(uint i = 0; i < tokensLength; i++){
                uint256 currentTokenBalance = IERC20Local(trackedTokens[i]).balanceOf(_user);

                memDeltas[i].value = currentTokenBalance  > prevTokenBalance[i] ? (currentTokenBalance - prevTokenBalance[i]) : (prevTokenBalance[i] - currentTokenBalance);
                memDeltas[i].sign = currentTokenBalance  > prevTokenBalance[i] ? ('+') : ('-');
            }    
            tokenDeltas = memDeltas;
        }
    }
}