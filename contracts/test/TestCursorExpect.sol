// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {Blocks, Cursors} from "../Codec.sol";
import {Position, PositionConstraints} from "../core/Types.sol";
import {POSITION_CONSTRAINTS_HEADER} from "../codec/Specs.sol";
import {Headers} from "../codec/Headers.sol";
import {INVALID_BLOCK, OUT_OF_BOUNDS, UNEXPECTED_VALUE, OUT_OF_RANGE, OutOfBounds, UnexpectedValue, OutOfRange} from "../utils/Errors.sol";

import {ReadCompareCursorBlocks} from "./ReadCompareCursorBlocks.sol";

library CursorExpectCandidates {
    function fixedEnd(uint cur) private pure returns (uint end) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            if iszero(eq(shr(192, calldataload(start)), POSITION_CONSTRAINTS_HEADER)) {
                mstore(0, INVALID_BLOCK) revert(28, 4)
            }
            end := add(start, 136)
            if gt(end, and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
        }
    }
    function wordAt(uint abs) private pure returns (bytes32 value) {
        assembly ("memory-safe") { value := calldataload(abs) }
    }
    function readable(uint cur, Position memory position) internal pure returns (uint blockCur) {
        uint end = fixedEnd(cur);
        unchecked {
            uint body = uint(uint32(cur)) + 8;
            if (wordAt(body) != position.asset || wordAt(body + 64) != position.liability) revert UnexpectedValue();
            if (position.amount < uint(wordAt(body + 32)) || position.debt > uint(wordAt(body + 96))) revert OutOfRange();
            return uint32(cur) | (end << 32);
        }
    }
    function packed(uint cur, Position memory position) internal pure returns (uint blockCur) {
        (blockCur, ) = Blocks.takeFixed(cur, Headers.PositionConstraints);
        unchecked {
            uint body = uint(uint32(cur)) + 8;
            if (wordAt(body) != position.asset || wordAt(body + 64) != position.liability) revert UnexpectedValue();
            if (position.amount < uint(wordAt(body + 32)) || position.debt > uint(wordAt(body + 96))) revert OutOfRange();
        }
    }
    function grouped(uint cur, Position memory position) internal pure returns (uint blockCur) {
        uint end = fixedEnd(cur);
        bool mismatch; bool outside;
        assembly ("memory-safe") {
            let body := add(and(cur, 0xffffffff), 8)
            mismatch := or(iszero(eq(calldataload(body), mload(position))),
                           iszero(eq(calldataload(add(body, 64)), mload(add(position, 64)))))
            outside := or(lt(mload(add(position, 32)), calldataload(add(body, 32))),
                          gt(mload(add(position, 96)), calldataload(add(body, 96))))
        }
        if (mismatch) revert UnexpectedValue();
        if (outside) revert OutOfRange();
        return uint32(cur) | (end << 32);
    }
    function fused(uint cur, Position memory position) internal pure returns (uint blockCur) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            if iszero(eq(shr(192, calldataload(start)), POSITION_CONSTRAINTS_HEADER)) {
                mstore(0, INVALID_BLOCK) revert(28, 4)
            }
            let end := add(start, 136)
            if gt(end, and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            if or(iszero(eq(calldataload(add(start, 8)), mload(position))),
                  iszero(eq(calldataload(add(start, 72)), mload(add(position, 64))))) {
                mstore(0, UNEXPECTED_VALUE) revert(28, 4)
            }
            if or(lt(mload(add(position, 32)), calldataload(add(start, 40))),
                  gt(mload(add(position, 96)), calldataload(add(start, 104)))) {
                mstore(0, OUT_OF_RANGE) revert(28, 4)
            }
            blockCur := or(start, shl(32, end))
        }
    }
    function decoded(uint cur, Position memory position) internal pure returns (uint blockCur) {
        // Decode to memory for comparison; bounds are established before reads.
        uint start = uint32(cur);
        uint end = start + 136;
        if (end > uint32(cur >> 32)) revert OutOfBounds();
        PositionConstraints memory value = LegacyBlocks.unpackPositionConstraints(start);
        if (value.asset != position.asset || value.liability != position.liability) revert UnexpectedValue();
        if (position.amount < value.amount || position.debt > value.debt) revert OutOfRange();
        return start | (end << 32);
    }
}

abstract contract CursorExpectHarness {
    function check(uint cur, Position memory position) internal pure virtual returns (uint blockCur);
    function inspect(bytes calldata source, uint length, uint offset, Position memory position)
        external pure returns (uint blockCur, uint base, Position memory unchanged)
    {
        require(length <= source.length);
        base = Cursors.base(source);
        blockCur = check((base + offset) | ((base + length) << 32) | (uint(0xabcdef) << 64), position);
        unchanged = position;
    }
    function onlyCheck(bytes calldata source, Position memory position) external pure {
        check(Cursors.wrap(source), position);
    }
    function measure(bytes calldata source, Position memory position) external view virtual returns (uint gasUsed, uint count, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint blockCur = check(cur, position);
            cur = (cur & ~uint(type(uint32).max)) | (blockCur >> 32);
            unchecked { ++count; }
        }
        gasUsed = beforeGas - gasleft();
    }
    function measureDiscard(bytes calldata source, Position memory position) external view returns (uint gasUsed, uint count, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            check(cur, position);
            unchecked { cur += 136; ++count; }
        }
        gasUsed = beforeGas - gasleft();
    }
    function measureAttempt(bytes calldata source, Position memory position) external view returns (uint gasUsed, bool ok, bytes memory reason) {
        bytes memory input = abi.encodeCall(this.onlyCheck, (source, position));
        uint beforeGas = gasleft();
        (ok, reason) = address(this).staticcall(input);
        gasUsed = beforeGas - gasleft();
    }
}

contract CursorExpectBaseline is CursorExpectHarness {
    function check(uint cur, Position memory position) internal pure override returns (uint blockCur) {
        uint start = uint32(cur);
        uint end = start + 136;
        if (end > uint32(cur >> 32)) revert OutOfBounds();
        LegacyBlocks.expectPositionConstraints(start, position);
        return start | (end << 32);
    }
}
contract CursorExpectReadable is CursorExpectHarness {
    function check(uint cur, Position memory position) internal pure override returns (uint blockCur) {
        return CursorExpectCandidates.readable(cur, position);
    }
}
contract CursorExpectPacked is CursorExpectHarness {
    function check(uint cur, Position memory position) internal pure override returns (uint blockCur) {
        return CursorExpectCandidates.packed(cur, position);
    }
}
contract CursorExpectGrouped is CursorExpectHarness {
    function check(uint cur, Position memory position) internal pure override returns (uint blockCur) {
        return CursorExpectCandidates.grouped(cur, position);
    }
}
contract CursorExpectFused is CursorExpectHarness {
    function check(uint cur, Position memory position) internal pure override returns (uint blockCur) {
        return CursorExpectCandidates.fused(cur, position);
    }
}
contract CursorExpectDecoded is CursorExpectHarness {
    function check(uint cur, Position memory position) internal pure override returns (uint blockCur) {
        return CursorExpectCandidates.decoded(cur, position);
    }
}
contract CursorExpectCurrent is CursorExpectHarness {
    function check(uint cur, Position memory position) internal pure override returns (uint nextCur) {
        return Blocks.expectPositionConstraints(cur, position);
    }
    function measure(bytes calldata source, Position memory position) external view override returns (uint gasUsed, uint count, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            cur = Blocks.expectPositionConstraints(cur, position);
            unchecked { ++count; }
        }
        gasUsed = beforeGas - gasleft();
    }
    function inspectMetadata(bytes calldata source, uint length, uint offset, uint metadata, Position memory position)
        external pure returns (uint nextCur, uint originalCur, uint baseAbs)
    {
        require(length <= source.length);
        baseAbs = Cursors.base(source);
        originalCur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        nextCur = Blocks.expectPositionConstraints(originalCur, position);
    }
}

contract CursorExpectReadCompare is CursorExpectHarness {
    function check(uint cur, Position memory position) internal pure override returns (uint blockCur) {
        return ReadCompareCursorBlocks.expectPositionConstraints(cur, position);
    }
}
