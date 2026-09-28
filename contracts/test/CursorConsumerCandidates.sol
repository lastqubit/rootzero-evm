// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";
import {Position} from "../core/Types.sol";
import {LegacyHeaders} from "./LegacyHeaders.sol";
import {INVALID_BLOCK, OUT_OF_BOUNDS, UNEXPECTED_VALUE, OUT_OF_RANGE} from "../utils/Errors.sol";

/// @dev Test-only candidate: extract the absolute position once per operation.
library CursorConsumerPrimitives {
    function fixedAt(uint abs, uint endAbs, uint64 header) private pure {
        assembly ("memory-safe") {
            if iszero(eq(shr(192, calldataload(abs)), header)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            if gt(add(add(abs, 8), and(header, 0xffffffff)), endAbs) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
        }
    }
    function unpackBalance(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        uint abs = uint32(cur);
        fixedAt(abs, uint32(cur >> 32), LegacyHeaders.Balance);
        unchecked {
            asset = Blocks.read32(abs + 8);
            amount = uint(Blocks.read32(abs + 40));
            nextCur = cur + 72;
        }
    }
    function expectPositionConstraints(uint cur, Position memory position) internal pure returns (uint nextCur) {
        uint abs = uint32(cur);
        fixedAt(abs, uint32(cur >> 32), LegacyHeaders.PositionConstraints);
        assembly ("memory-safe") {
            if or(iszero(eq(calldataload(add(abs, 8)), mload(position))), iszero(eq(calldataload(add(abs, 72)), mload(add(position, 64))))) {
                mstore(0, UNEXPECTED_VALUE) revert(28, 4)
            }
            if or(gt(calldataload(add(abs, 40)), mload(add(position, 32))), lt(calldataload(add(abs, 104)), mload(add(position, 96)))) {
                mstore(0, OUT_OF_RANGE) revert(28, 4)
            }
        }
        unchecked { nextCur = cur + 136; }
    }
    function take(uint cur, bytes4 key) internal pure returns (uint blockCur) {
        uint abs = uint32(cur);
        uint expected = uint32(key);
        assembly ("memory-safe") {
            let head := calldataload(abs)
            if iszero(eq(shr(224, head), expected)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            let endAbs := add(add(abs, 8), and(shr(192, head), 0xffffffff))
            if gt(endAbs, and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            blockCur := or(abs, shl(32, endAbs))
        }
    }
}

/// @dev Test-only control: fuse fixed validation, reads and advancement.
library CursorConsumerFused {
    function unpackBalance(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        uint64 header = LegacyHeaders.Balance;
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            if iszero(eq(shr(192, calldataload(abs)), header)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            if gt(add(abs, 72), and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
            nextCur := add(cur, 72)
        }
    }
    function expectPositionConstraints(uint cur, Position memory position) internal pure returns (uint nextCur) {
        uint64 header = LegacyHeaders.PositionConstraints;
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            if iszero(eq(shr(192, calldataload(abs)), header)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            if gt(add(abs, 136), and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            if or(iszero(eq(calldataload(add(abs, 8)), mload(position))), iszero(eq(calldataload(add(abs, 72)), mload(add(position, 64))))) {
                mstore(0, UNEXPECTED_VALUE) revert(28, 4)
            }
            if or(gt(calldataload(add(abs, 40)), mload(add(position, 32))), lt(calldataload(add(abs, 104)), mload(add(position, 96)))) {
                mstore(0, OUT_OF_RANGE) revert(28, 4)
            }
            nextCur := add(cur, 136)
        }
    }
    function take(uint cur, bytes4 key) internal pure returns (uint blockCur) {
        return CursorConsumerPrimitives.take(cur, key);
    }
}

/// @dev Reduced-argument shared primitive; full header is kept as uint.
library CursorConsumerCompact {
    function fixedAt(uint cur, uint header) private pure returns (uint abs) {
        assembly ("memory-safe") {
            abs := and(cur, 0xffffffff)
            if iszero(eq(shr(192, calldataload(abs)), header)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            if gt(add(add(abs, 8), and(header, 0xffffffff)), and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
        }
    }
    function unpackBalance(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        uint abs = fixedAt(cur, LegacyHeaders.Balance);
        unchecked {
            asset = Blocks.read32(abs + 8);
            amount = uint(Blocks.read32(abs + 40));
            nextCur = cur + 72;
        }
    }
    function expectPositionConstraints(uint cur, Position memory position) internal pure returns (uint nextCur) {
        uint abs = fixedAt(cur, LegacyHeaders.PositionConstraints);
        assembly ("memory-safe") {
            if or(iszero(eq(calldataload(add(abs, 8)), mload(position))), iszero(eq(calldataload(add(abs, 72)), mload(add(position, 64))))) {
                mstore(0, UNEXPECTED_VALUE) revert(28, 4)
            }
            if or(gt(calldataload(add(abs, 40)), mload(add(position, 32))), lt(calldataload(add(abs, 104)), mload(add(position, 96)))) {
                mstore(0, OUT_OF_RANGE) revert(28, 4)
            }
        }
        unchecked { nextCur = cur + 136; }
    }
    function take(uint cur, bytes4 key) internal pure returns (uint blockCur) {
        uint abs = uint32(cur);
        uint expected = uint32(key);
        assembly ("memory-safe") {
            let head := calldataload(abs)
            if iszero(eq(shr(224, head), expected)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            let endAbs := add(add(abs, 8), and(shr(192, head), 0xffffffff))
            if gt(endAbs, and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            blockCur := or(abs, shl(32, endAbs))
        }
    }
}
