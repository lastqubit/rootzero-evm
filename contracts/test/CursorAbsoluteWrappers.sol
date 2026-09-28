// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyHeaders} from "./LegacyHeaders.sol";
import {STEP_KEY, BYTES_KEY} from "../codec/Keys.sol";
import {Position} from "../core/Types.sol";
import {INVALID_BLOCK, OUT_OF_BOUNDS, UNEXPECTED_VALUE, OUT_OF_RANGE} from "../utils/Errors.sol";

/// @dev Test-only absolute decoders with thin packed-cursor adapters.
/// Primitives own all validation. Wrappers only convert representations/advance.
/// Private absolute inputs originate from uint32 cursor lanes; derived ends stay
/// full-width until containment succeeds. No wrapper repeats a bounds check.
library CursorAbsoluteWrappers {
    function unpackBalanceAt(uint abs, uint endAbs) private pure returns (bytes32 asset, uint amount) {
        uint64 header = LegacyHeaders.Balance;
        assembly ("memory-safe") {
            if iszero(eq(shr(192, calldataload(abs)), header)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            if gt(add(abs, 72), endAbs) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            asset := calldataload(add(abs, 8))
            amount := calldataload(add(abs, 40))
        }
    }
    function expectPositionConstraintsAt(uint abs, uint endAbs, Position memory position) private pure {
        uint64 header = LegacyHeaders.PositionConstraints;
        assembly ("memory-safe") {
            if iszero(eq(shr(192, calldataload(abs)), header)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            if gt(add(abs, 136), endAbs) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            if or(iszero(eq(calldataload(add(abs, 8)), mload(position))), iszero(eq(calldataload(add(abs, 72)), mload(add(position, 64))))) {
                mstore(0, UNEXPECTED_VALUE) revert(28, 4)
            }
            if or(gt(calldataload(add(abs, 40)), mload(add(position, 32))), lt(calldataload(add(abs, 104)), mload(add(position, 96)))) {
                mstore(0, OUT_OF_RANGE) revert(28, 4)
            }
        }
    }
    function endAt(uint abs, uint limit, bytes4 key) private pure returns (uint endAbs) {
        uint expected = uint32(key);
        assembly ("memory-safe") {
            let head := calldataload(abs)
            if iszero(eq(shr(224, head), expected)) { mstore(0, INVALID_BLOCK) revert(28, 4) }
            endAbs := add(add(abs, 8), and(shr(192, head), 0xffffffff))
            if gt(endAbs, limit) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
        }
    }
    function unpackStepAt(uint abs, uint limit) private pure returns (uint cmd, uint value, uint inputAbs, uint endAbs) {
        endAbs = endAt(abs, limit, bytes4(uint32(STEP_KEY)));
        assembly ("memory-safe") {
            inputAbs := add(abs, 80)
            if or(lt(endAbs, inputAbs), iszero(eq(shr(192, calldataload(add(abs, 72))), or(shl(32, BYTES_KEY), sub(endAbs, inputAbs))))) {
                mstore(0, INVALID_BLOCK) revert(28, 4)
            }
            cmd := calldataload(add(abs, 8))
            value := calldataload(add(abs, 40))
        }
    }
    function unpackBalance(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        (asset, amount) = unpackBalanceAt(uint32(cur), uint32(cur >> 32));
        unchecked { nextCur = cur + 72; }
    }
    function expectPositionConstraints(uint cur, Position memory position) internal pure returns (uint nextCur) {
        expectPositionConstraintsAt(uint32(cur), uint32(cur >> 32), position);
        unchecked { nextCur = cur + 136; }
    }
    function take(uint cur, bytes4 key) internal pure returns (uint blockCur) {
        uint abs = uint32(cur);
        uint endAbs = endAt(abs, uint32(cur >> 32), key);
        blockCur = abs | (endAbs << 32);
    }
    function unpackStep(uint cur) internal pure returns (uint cmd, uint value, uint inputCur, uint nextCur) {
        uint inputAbs; uint endAbs;
        (cmd, value, inputAbs, endAbs) = unpackStepAt(uint32(cur), uint32(cur >> 32));
        inputCur = inputAbs | (endAbs << 32);
        nextCur = (cur & ~uint(type(uint32).max)) | endAbs;
    }
}
