// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyHeaders} from "./LegacyHeaders.sol";
import {Position} from "../core/Types.sol";
import {INVALID_BLOCK, OUT_OF_BOUNDS, UnexpectedValue, OutOfRange} from "../utils/Errors.sol";

/// @dev Frozen read-then-compare implementation, before adding comparison primitives.
library ReadCompareCursorBlocks {
    function expectPositionConstraints(uint cur, Position memory position) internal pure returns (uint blockCur) {
        uint end = fixedEnd(cur, LegacyHeaders.PositionConstraints);
        unchecked {
            uint body = uint(uint32(cur)) + 8;
            if (either(read32(body) != position.asset, read32(body + 64) != position.liability)) revert UnexpectedValue();
            if (either(position.amount < uint(read32(body + 32)), position.debt > uint(read32(body + 96)))) revert OutOfRange();
            return pack(uint32(cur), end);
        }
    }

    function fixedEnd(uint cur, uint64 expected) private pure returns (uint end) {
        return boundedEnd(cur, fixedLength(cur, expected));
    }

    function fixedLength(uint cur, uint64 expected) private pure returns (uint len) {
        assembly ("memory-safe") {
            if iszero(eq(shr(192, calldataload(and(cur, 0xffffffff))), and(expected, 0xffffffffffffffff))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            len := and(expected, 0xffffffff)
        }
    }

    function boundedEnd(uint cur, uint len) private pure returns (uint end) {
        end = endAt(cur, len);
        assembly ("memory-safe") {
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
        }
    }

    function endAt(uint cur, uint len) private pure returns (uint end) {
        assembly ("memory-safe") { end := add(add(and(cur, 0xffffffff), 8), len) }
    }

    function read32(uint abs) internal pure returns (bytes32 value) {
        assembly ("memory-safe") { value := calldataload(abs) }
    }

    function either(bool a, bool b) private pure returns (bool result) {
        assembly ("memory-safe") { result := or(a, b) }
    }

    function pack(uint start, uint end) private pure returns (uint result) {
        assembly ("memory-safe") { result := or(start, shl(32, end)) }
    }
}
