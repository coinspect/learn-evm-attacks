pragma solidity ^0.8.17;
library Strings {
    /**
     * @dev Creates a padding of 'length' zeroes.
     */
    function repeat(string memory value, uint256 times) pure internal returns(string memory) {
      string memory result;
      for (uint8 i = 0; i < times; i++) {
         result = string.concat(result, value);
      }
      return result;
    }


    function length(string memory s) internal pure returns (uint256) {
        uint256 len;
        uint256 i = 0;
        uint256 bytelength = bytes(s).length;
        for (len = 0; i < bytelength; len++) {
            bytes1 b = bytes(s)[i];
            if (b < 0x80) {
                i += 1;
            } else if (b < 0xE0) {
                i += 2;
            } else if (b < 0xF0) {
                i += 3;
            } else if (b < 0xF8) {
                i += 4;
            } else if (b < 0xFC) {
                i += 5;
            } else {
                i += 6;
            }
        }
        return len;
    }


}

library UintToString {
    using Strings for string;
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

        function toStringWithDecimals(uint256 _number, uint8 decimals) internal pure returns(string memory){
        uint256 integer = _number / (10**decimals);
        uint256 fraction = (_number % (10**decimals));
        string memory integerString = toString(integer);
        string memory fractionString = toString(fraction);
        if (fraction == 0) {
          return toString(integer);
        }
        string memory padding = '0';
        return string.concat(integerString, '.', padding.repeat(decimals - fractionString.length()), fractionString);
    }
}




