// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Independent RFC 4648 decoder for testing the production encoder's data URIs.
library MetadataDecoder {
    function decodeURI(string memory uri, string memory prefix) internal pure returns (string memory) {
        bytes memory input = bytes(uri);
        bytes memory marker = bytes(prefix);
        require(input.length >= marker.length, "short URI");
        for (uint256 i; i < marker.length; ++i) {
            require(input[i] == marker[i], "wrong URI prefix");
        }
        uint256 length = input.length - marker.length;
        require(length > 0 && length % 4 == 0, "invalid base64 length");
        uint256 padding = input[input.length - 1] == "=" ? 1 : 0;
        if (input[input.length - 2] == "=") ++padding;
        bytes memory output = new bytes(length / 4 * 3 - padding);
        uint256 out;
        for (uint256 i = marker.length; i < input.length; i += 4) {
            uint256 word = (_value(input[i]) << 18) | (_value(input[i + 1]) << 12) | (_value(input[i + 2]) << 6)
                | _value(input[i + 3]);
            if (out < output.length) output[out++] = bytes1(uint8(word >> 16));
            if (out < output.length) output[out++] = bytes1(uint8(word >> 8));
            if (out < output.length) output[out++] = bytes1(uint8(word));
        }
        return string(output);
    }

    function contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i; i <= h.length - n.length; ++i) {
            bool equal = true;
            for (uint256 j; j < n.length; ++j) {
                if (h[i + j] != n[j]) {
                    equal = false;
                    break;
                }
            }
            if (equal) return true;
        }
        return false;
    }

    function _value(bytes1 char) private pure returns (uint256) {
        uint8 c = uint8(char);
        if (c >= 65 && c <= 90) return c - 65;
        if (c >= 97 && c <= 122) return c - 71;
        if (c >= 48 && c <= 57) return c + 4;
        if (char == "+") return 62;
        if (char == "/") return 63;
        require(char == "=", "invalid base64 character");
        return 0;
    }
}
