// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {INVALID_BLOCK, OUT_OF_BOUNDS, InvalidBlock} from "../utils/Errors.sol";

/// @title PreviousCursorBlocks
/// @notice Frozen initial implementation for entry/prefix gas comparisons.
/// @dev A cursor stores absolute position in bits 0-31 and exclusive end in
/// bits 32-63. Input metadata is ignored; returned cursors have no metadata.
/// Callers must establish that the supplied range belongs to calldata.
/// These helpers validate logical containment, not the source's provenance.
/// `take` returns the complete block; `enter` returns its payload. Neither
/// advances the caller's stream. Consumers may trust successful validation
/// and update stream positions without repeating bounds checks.
/// Shape errors precede bounds errors. A full-width end check proves both
/// header and payload containment, including for reversed input ranges.
library PreviousCursorBlocks {
    /// @notice Select one complete block without imposing a key or schema.
    /// @return blockCur Cursor spanning the header and payload.
    function take(uint cur) internal pure returns (uint blockCur) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            let len := and(shr(192, calldataload(start)), 0xffffffff)
            let end := add(add(start, 8), len)
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
            blockCur := or(start, shl(32, end))
        }
    }

    /// @notice Select one block matching the key and payload bounds in `spec`.
    /// @dev A zero maximum means unbounded, as in LegacyBlocks.enter.
    function take(uint cur, uint spec) internal pure returns (uint blockCur) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            let head := calldataload(start)
            let len := and(shr(192, head), 0xffffffff)
            let maximum := and(shr(160, spec), 0xffffffff)
            if or(
                or(iszero(eq(shr(224, head), shr(224, spec))), lt(len, and(shr(192, spec), 0xffffffff))),
                and(iszero(iszero(maximum)), gt(len, maximum))
            ) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            // start and len are uint32; their sum plus 8 fits uint256.
            // Check before packing so an end above uint32 cannot wrap.
            let end := add(add(start, 8), len)
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
            blockCur := or(start, shl(32, end))
        }
    }

    /// @notice Select one complete block with the expected key.
    /// @dev This does not establish a particular payload shape or field width.
    function take(uint cur, bytes4 key) internal pure returns (uint blockCur) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            let head := calldataload(start)
            if iszero(eq(shr(224, head), shr(224, key))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            let end := add(add(start, 8), and(shr(192, head), 0xffffffff))
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
            blockCur := or(start, shl(32, end))
        }
    }

    /// @notice Select a fixed-size block by its right-aligned key/length header.
    /// @param expected Exact uint64 header, such as Headers.Balance.
    function takeFixed(uint cur, uint64 expected) internal pure returns (uint blockCur) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            let header := shr(192, calldataload(start))
            if iszero(eq(header, and(expected, 0xffffffffffffffff))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            let end := add(add(start, 8), and(header, 0xffffffff))
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
            blockCur := or(start, shl(32, end))
        }
    }

    /// @notice Return the payload range of one schema-validated block.
    function enter(uint cur, uint spec) internal pure returns (uint bodyCur) {
        // take proved that adding the header cannot carry into the end lane.
        unchecked { bodyCur = take(cur, spec) + 8; }
    }

    /// @notice Return the payload range of one key-validated block.
    function enter(uint cur, bytes4 key) internal pure returns (uint bodyCur) {
        unchecked { bodyCur = take(cur, key) + 8; }
    }

    /// @notice Enter a schema-validated payload after a fixed byte prefix.
    /// @return bodyCur Remaining payload range, including an empty remainder.
    function enter(uint cur, uint spec, uint amount) internal pure returns (uint bodyCur) {
        bodyCur = skipPrefix(enter(cur, spec), amount);
    }

    /// @notice Enter a key-validated payload after a fixed byte prefix.
    function enter(uint cur, bytes4 key, uint amount) internal pure returns (uint bodyCur) {
        bodyCur = skipPrefix(enter(cur, key), amount);
    }

    /// @dev Only called with a validated payload; the prefix is a new constraint.
    function skipPrefix(uint bodyCur, uint amount) private pure returns (uint) {
        unchecked {
            if (amount > (bodyCur >> 32) - uint32(bodyCur)) revert InvalidBlock();
            return bodyCur + amount;
        }
    }

    /// @notice Require exactly one matching block and return its payload cursor.
    /// @dev Like LegacyBlocks.exact, trailing bytes or truncation are InvalidBlock.
    /// Equality with the source end also proves containment; do not check twice.
    function exact(uint cur, uint spec) internal pure returns (uint bodyCur) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            let head := calldataload(start)
            let len := and(shr(192, head), 0xffffffff)
            let maximum := and(shr(160, spec), 0xffffffff)
            if or(
                or(iszero(eq(shr(224, head), shr(224, spec))), lt(len, and(shr(192, spec), 0xffffffff))),
                and(iszero(iszero(maximum)), gt(len, maximum))
            ) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            let body := add(start, 8)
            let end := add(body, len)
            if iszero(eq(end, and(shr(32, cur), 0xffffffff))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            bodyCur := or(body, shl(32, end))
        }
    }
}
