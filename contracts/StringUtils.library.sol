// SPDX-License-Identifier: UNLICENSED
pragma solidity ~0.8.22;

library StringUtils {
    // bytes[6] utf_8_1byte_whiteSpaces = [0x20, 0x09, 0x0c, 0x1c, 0x1e, 0x1f];
    // bytes[6] utf_8_1byte_whiteSpaces = [0x20, 0x09, 0x0c, 0x1c, 0x1e, 0x1f];
    // bytes[6] utf_8_1byte_whiteSpaces = [0x20, 0x09, 0x0c, 0x1c, 0x1e, 0x1f];

    function length(string memory str) public pure returns (uint256) {
        bytes memory strBytes = bytes(str);
        uint256 charCount = 0;
        uint256 i = 0;

        // Identify character size by using first byte
        while (i < strBytes.length) {
            if ((strBytes[i] >> 7) == 0) {
                // 1-byte character (0xxxxxxx)
                i += 1;
            } else if (strBytes[i] >= 0xc2 && strBytes[i] <= 0xdf) { // equivalent to (strBytes[i] >> 5) == 5 (or 0b110)
                // 2-byte character (110xxxxx)
                i += 2;
            } else if (strBytes[i] >= 0xe0 && strBytes[i] <= 0xef) { // equivalent to (strBytes[i] >> 4) == 14 (or 0b1110)
                // 3-byte character (1110xxxx)
                i += 3;
            } else if (strBytes[i] == 0xf0 && strBytes[i] <= 0xf4) { // equivalent to (strBytes[i] >> 3) == 30 (or 0b1111b)
                // 4-byte character (11110xxx)
                i += 4;
            } else {
                // Invalid UTF-8 character
                revert("Invalid UTF-8 encoding");
            }

            charCount++;
        }

        require(i == strBytes.length, "Invalid UTF-8 character exists");
        return charCount;
    }

    function isBlank(string memory str) public pure returns (bool) {
        bytes memory strBytes = bytes(str);

        if (strBytes.length == 0) {
            return true;
        }

        bytes1[] memory utf8WhiteSpaceCharacters = new bytes1[](8);
        uint256 i = 0;
   
        utf8WhiteSpaceCharacters[i++] = 0x20; // Space (normal space)
        utf8WhiteSpaceCharacters[i++] = 0x09; // Horizontal Tab (Tab)
        utf8WhiteSpaceCharacters[i++] = 0x0A; // Line Feed (LF / New Line)
        utf8WhiteSpaceCharacters[i++] = 0x0B; // Vertical Tab
        utf8WhiteSpaceCharacters[i++] = 0x0C; // Form Feed (FF)
        utf8WhiteSpaceCharacters[i++] = 0x0D; // Carriage Return (CR)
        utf8WhiteSpaceCharacters[i++] = 0x85; // Next Line (NEL)
        utf8WhiteSpaceCharacters[i++] = 0xA0; // No-Break Space
        
        i = 0;

        // Identify character size by using first byte
        while (i < strBytes.length) {
            if ((strBytes[i] >> 7) == 0) {
                // 1-byte character (0xxxxxxx)
                if (_contains(utf8WhiteSpaceCharacters, strBytes[i])) {
                    return false;
                }

                i += 1;
            } else if (strBytes[i] >= 0xc2 && strBytes[i] <= 0xdf) { // equivalent to (strBytes[i] >> 5) == 5 (or 0b110)
                // 2-byte character (110xxxxx)
                i += 2;
            } else if (strBytes[i] >= 0xe0 && strBytes[i] <= 0xef) { // equivalent to (strBytes[i] >> 4) == 14 (or 0b1110)
                // 3-byte character (1110xxxx)
                i += 3;
            } else if (strBytes[i] == 0xf0 && strBytes[i] <= 0xf4) { // equivalent to (strBytes[i] >> 3) == 30 (or 0b1111b)
                // 4-byte character (11110xxx)
                i += 4;
            } else {
                // Invalid UTF-8 character
                revert("Invalid UTF-8 encoding");
            }
        }

        return true;
    }

    function _contains(bytes1[] memory arr, bytes1 value) private pure returns (bool) {
        for (uint16 i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                return true;
            }
        }

        return false;
    }

    function isUTF8Character(string memory char) public pure returns (bool) {
        bytes memory strBytes = bytes(char);
     
        if (strBytes.length > 4) {
            return false;
        }

        if ((strBytes[0] >> 7) == 0) {
                // 1-byte character (0xxxxxxx)
            return true;
        } else if (strBytes[0] >= 0xc2 && strBytes[0] <= 0xdf) { // equivalent to (strBytes[0] >> 5) == 5 (or 0b110)
            // 2-byte character (110xxxxx)
            return true;
        } else if (strBytes[0] >= 0xe0 && strBytes[0] <= 0xef) { // equivalent to (strBytes[0] >> 4) == 14 (or 0b1110)
            // 3-byte character (1110xxxx)
            return true;
        } else if (strBytes[0] == 0xf0 && strBytes[0] <= 0xf4) { // equivalent to (strBytes[0] >> 3) == 30 (or 0b1111b)
            // 4-byte character (11110xxx)
            return true;
        } else {
            // Invalid UTF-8 character
            return false;
        }
    }
}