// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {INVALID_BLOCK, OUT_OF_BOUNDS} from "../utils/Errors.sol";
// Measured alternatives: each entry path validates and packs only once.
library CursorEntryCandidates {
    function enter(uint cur, uint spec) internal pure returns (uint blockCur) {
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
            blockCur := or(add(start, 8), shl(32, end))
        }
    }
    function enter(uint cur, uint spec, uint amount) internal pure returns (uint blockCur) {
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
            if gt(amount, sub(sub(end, start), 8)) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            blockCur := or(add(add(start, 8), amount), shl(32, end))
        }
    }
    function enterLen(uint cur, uint spec, uint amount) internal pure returns (uint blockCur) {
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
            if gt(amount, len) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            blockCur := or(add(add(start, 8), amount), shl(32, end))
        }
    }
    function enter(uint cur, bytes4 key) internal pure returns (uint blockCur) {
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
            blockCur := or(add(start, 8), shl(32, end))
        }
    }
    function enter(uint cur, bytes4 key, uint amount) internal pure returns (uint blockCur) {
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
            if gt(amount, sub(sub(end, start), 8)) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            blockCur := or(add(add(start, 8), amount), shl(32, end))
        }
    }
    function enterLen(uint cur, bytes4 key, uint amount) internal pure returns (uint blockCur) {
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
            if gt(amount, and(shr(192, head), 0xffffffff)) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            blockCur := or(add(add(start, 8), amount), shl(32, end))
        }
    }
    function fixedExpected(uint cur, uint64 expected) internal pure returns (uint blockCur) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            let header := shr(192, calldataload(start))
            if iszero(eq(header, and(expected, 0xffffffffffffffff))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            let end := add(add(start, 8), and(expected, 0xffffffff))
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
            blockCur := or(start, shl(32, end))
        }
    }
}
