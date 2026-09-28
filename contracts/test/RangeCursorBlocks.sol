// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Keys} from "../codec/Keys.sol";
import {INVALID_BLOCK, OUT_OF_BOUNDS} from "../utils/Errors.sol";

/// @dev Frozen pre-advancement unpackers for historical range-return comparisons only.
library RangeCursorBlocks {
    function unpack64(uint cur, bytes4 key) internal pure returns (bytes32 a, bytes32 b, uint blockCur) {
        uint endAbs = fixedEnd(cur, (uint64(uint32(key)) << 32) | 64);
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            a := calldataload(add(abs, 8))
            b := calldataload(add(abs, 40))
        }
        blockCur = pack(uint32(cur), endAbs);
    }

    function unpackBalance(uint cur) internal pure returns (bytes32 asset, uint amount, uint blockCur) {
        bytes32 value;
        (asset, value, blockCur) = unpack64(cur, Keys.Balance);
        amount = uint(value);
    }

    function unpackStep(uint cur) internal pure returns (uint cmd, uint value, uint inputCur) {
        uint endAbs = boundedEnd(cur, payloadLength(cur, Keys.Step));
        // uint32 position + 72 cannot overflow uint256; tail proves it fits endAbs.
        unchecked { inputCur = tail(uint(uint32(cur)) + 72, endAbs, Keys.Bytes); }
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            cmd := calldataload(add(abs, 8))
            value := calldataload(add(abs, 40))
        }
    }

    function unpackRelay(uint cur) internal pure returns (uint inputCur, uint stepsCur) {
        uint endAbs = boundedEnd(cur, payloadLength(cur, Keys.Relay));
        unchecked { return pair(uint(uint32(cur)) + 8, endAbs, Keys.Bytes); }
    }

    function unpackContext(uint cur) internal pure returns (bytes32 account, uint stateCur, uint inputCur) {
        uint endAbs = boundedEnd(cur, payloadLength(cur, Keys.Context));
        unchecked { (stateCur, inputCur) = pair(uint(uint32(cur)) + 40, endAbs, Keys.Bytes); }
        assembly ("memory-safe") { account := calldataload(add(and(cur, 0xffffffff), 8)) }
    }

    function unpack160(uint cur, bytes4 key) internal pure returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e, uint blockCur) {
        uint endAbs = fixedEnd(cur, (uint64(uint32(key)) << 32) | 160);
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            a := calldataload(add(abs, 8))
            b := calldataload(add(abs, 40))
            c := calldataload(add(abs, 72))
            d := calldataload(add(abs, 104))
            e := calldataload(add(abs, 136))
        }
        blockCur = pack(uint32(cur), endAbs);
    }

    function payloadLength(uint cur, uint spec) private pure returns (uint len) {
        assembly ("memory-safe") {
            let head := calldataload(and(cur, 0xffffffff))
            len := and(shr(192, head), 0xffffffff)
            let maximum := and(shr(160, spec), 0xffffffff)
            if or(
                or(iszero(eq(shr(224, head), shr(224, spec))), lt(len, and(shr(192, spec), 0xffffffff))),
                and(iszero(iszero(maximum)), gt(len, maximum))
            ) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
        }
    }

    function payloadLength(uint cur, bytes4 key) private pure returns (uint len) {
        return lengthAt(uint32(cur), key);
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

    function fixedEnd(uint cur, uint64 expected) private pure returns (uint endAbs) {
        return boundedEnd(cur, fixedLength(cur, expected));
    }

    function endAt(uint cur, uint len) private pure returns (uint endAbs) {
        assembly ("memory-safe") { endAbs := add(add(and(cur, 0xffffffff), 8), len) }
    }

    function boundedEnd(uint cur, uint len) private pure returns (uint endAbs) {
        endAbs = endAt(cur, len);
        assembly ("memory-safe") {
            if gt(endAbs, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
        }
    }

    function read32(uint abs) internal pure returns (bytes32 value) {
        assembly ("memory-safe") { value := calldataload(abs) }
    }

    function pair(uint abs, uint endAbs, bytes4 key) private pure returns (uint firstCur, uint lastCur) {
        uint len = lengthAt(abs, key);
        unchecked {
            uint bodyAbs = abs + 8;
            uint nextAbs = bodyAbs + len;
            lastCur = tail(nextAbs, endAbs, key);
            firstCur = pack(bodyAbs, nextAbs);
        }
    }

    function tail(uint abs, uint endAbs, bytes4 key) private pure returns (uint resultCur) {
        assembly ("memory-safe") {
            let bodyAbs := add(abs, 8)
            let len := sub(endAbs, bodyAbs)
            if or(lt(endAbs, bodyAbs), iszero(eq(shr(192, calldataload(abs)), or(shl(32, shr(224, key)), len)))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            resultCur := or(bodyAbs, shl(32, endAbs))
        }
    }

    function pack(uint abs, uint endAbs) private pure returns (uint resultCur) {
        assembly ("memory-safe") { resultCur := or(abs, shl(32, endAbs)) }
    }

    function either(bool a, bool b) private pure returns (bool result) {
        assembly ("memory-safe") { result := or(a, b) }
    }
    function lengthAt(uint abs, bytes4 key) private pure returns (uint len) {
        assembly ("memory-safe") {
            let head := calldataload(abs)
            if iszero(eq(shr(224, head), shr(224, key))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            len := and(shr(192, head), 0xffffffff)
        }
    }
}
