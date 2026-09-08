// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {Sizes} from "../codec/Specs.sol";

/// @dev Frozen bounded inspection implementations for differential testing.
library PreviousBlockInspection {
    function peek(uint abs, uint end) internal pure returns (bytes4 key, uint len) {
        if (abs > end || Sizes.Header > end - abs) revert Blocks.MalformedBlocks();
        (key, len) = Blocks.header(abs);
        if (len > end - abs - Sizes.Header) revert Blocks.MalformedBlocks();
    }

    function hasAt(uint abs, uint end, bytes4 key) internal pure returns (bool) {
        if (abs > end || Sizes.Header > end - abs) return false;
        return bytes4(Blocks.read32(abs)) == key;
    }

    function isEmpty(uint abs, uint end, bytes4 key) internal pure returns (bool) {
        if (abs > end || Sizes.Header > end - abs) return false;
        uint head = uint(Blocks.read32(abs));
        return uint32(head >> 224) == uint32(key) && uint32(head >> 192) == 0;
    }
}

contract TestBlockInspection {
    function inspect(bool optimized, uint mode, bytes calldata input, uint start, uint length, bytes4 key, uint repetitions)
        external view returns (uint usedGas, bytes4 actual, uint len, bool matches)
    {
        uint abs;
        assembly ("memory-safe") { abs := input.offset }
        uint limit = abs + length;
        abs += start;
        uint initial = gasleft();
        for (uint i; i < repetitions; ++i) {
            if (mode == 0) {
                if (optimized) (actual, len) = Blocks.peek(abs, limit);
                else (actual, len) = PreviousBlockInspection.peek(abs, limit);
            } else if (mode == 1) {
                matches = optimized ? Blocks.hasAt(abs, limit, key) : PreviousBlockInspection.hasAt(abs, limit, key);
            } else {
                matches = optimized ? Blocks.isEmpty(abs, limit, key) : PreviousBlockInspection.isEmpty(abs, limit, key);
            }
        }
        usedGas = initial - gasleft();
    }

    /// @dev Raw uint256 positions exercise subtraction guards near overflow limits.
    function raw(bool optimized, uint mode, uint abs, uint end, bytes4 key)
        external pure returns (bytes4 actual, uint len, bool matches)
    {
        if (mode == 0) {
            if (optimized) (actual, len) = Blocks.peek(abs, end);
            else (actual, len) = PreviousBlockInspection.peek(abs, end);
        } else if (mode == 1) {
            matches = optimized ? Blocks.hasAt(abs, end, key) : PreviousBlockInspection.hasAt(abs, end, key);
        } else {
            matches = optimized ? Blocks.isEmpty(abs, end, key) : PreviousBlockInspection.isEmpty(abs, end, key);
        }
    }
}
