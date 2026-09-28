// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";
import {LegacyHeaders} from "./LegacyHeaders.sol";
import {BYTES_KEY} from "../codec/Keys.sol";
import {INVALID_BLOCK, OUT_OF_BOUNDS} from "../utils/Errors.sol";

library CursorFurtherCandidates {
    // Same validation and data as enter(cur, Bytes), plus source advancement.
    function unpackBytes(uint cur) internal pure returns (uint inputCur, uint nextCur) {
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            let head := calldataload(abs)
            if iszero(eq(shr(224, head), BYTES_KEY)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            let body := add(abs, 8)
            let endAbs := add(body, and(shr(192, head), 0xffffffff))
            if gt(endAbs, and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            inputCur := or(body, shl(32, endAbs))
            nextCur := or(and(cur, not(0xffffffff)), endAbs)
        }
    }
    function unpackBalanceRepack(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        uint64 header = LegacyHeaders.Balance;
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            if iszero(eq(shr(192, calldataload(abs)), header)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            let endAbs := add(abs, 72)
            if gt(endAbs, and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
            nextCur := or(and(cur, not(0xffffffff)), endAbs)
        }
    }
    function unpackBalanceReadFirst(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        uint64 header = LegacyHeaders.Balance;
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            let head := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
            if iszero(eq(head, header)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            if gt(add(abs, 72), and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            nextCur := add(cur, 72)
        }
    }
    function unpackBalanceSigned(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        uint64 header = LegacyHeaders.Balance;
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            let head := shr(192, calldataload(abs))
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
            if iszero(eq(head, header)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            if slt(sub(and(shr(32, cur), 0xffffffff), abs), 72) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            nextCur := add(cur, 72)
        }
    }
    function unpackBalanceAt(uint abs, uint endAbs) internal pure returns (bytes32 asset, uint amount) {
        uint64 header = LegacyHeaders.Balance;
        assembly ("memory-safe") {
            if iszero(eq(shr(192, calldataload(abs)), header)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            if gt(add(abs, 72), endAbs) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
        }
    }
    function unpackBytesComposed(uint cur) internal pure returns (uint inputCur, uint nextCur) {
        (inputCur, ) = Blocks.unpack(cur, bytes4(uint32(BYTES_KEY)));
        nextCur = (cur & ~uint(type(uint32).max)) | uint32(inputCur >> 32);
    }
    function unpackBalanceNextAt(uint abs, uint endAbs) internal pure returns (bytes32 asset, uint amount, uint nextAbs) {
        uint64 header = LegacyHeaders.Balance;
        assembly ("memory-safe") {
            if iszero(eq(shr(192, calldataload(abs)), header)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            nextAbs := add(abs, 72)
            if gt(nextAbs, endAbs) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
        }
    }
}
