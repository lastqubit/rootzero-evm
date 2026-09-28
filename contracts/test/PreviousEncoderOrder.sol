// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Keys} from "../codec/Keys.sol";
import {ValueOverflow} from "../utils/Errors.sol";

/// @title Encoder
/// @notice Experimental specialized encoders with memory and calldata-cursor overloads.
/// @dev Memory payloads use bytes; uint source cursors are validated packed calldata ranges.
/// Creators allocate only the final block. Cursor-first writers manage growable
/// buffers, including allocation, reservation, growth, and finalization.
/// Neither inspects nested stream contents. Absolute positions here refer to memory,
/// except the source position of the calldata copy primitive.
/// Creators always construct blocks from values and payloads, adding child headers.
/// Default composite writers copy complete children; their Wrap variants add child headers.
/// Cursor parameters use stateCur/inputCur in both; function names and NatSpec
/// specify whether their ranges include child headers.
library PreviousEncoderOrder {
    // General primitives: allocation, positions, sequential writes, and copies.

    /// @dev Allocate an uninitialized uint32-sized result with zero padding.
    /// Use pos(value, 0) for the first write position. Fill all logical bytes before
    /// exposing the result. Only the rounded final allocation is retained: writes
    /// may interleave allocations if they stay inside that owned extent. Any
    /// scratch beyond it must be used before further allocations.
    function allocate(uint size) internal pure returns (bytes memory value) {
        if (size > type(uint32).max) revert ValueOverflow();
        assembly ("memory-safe") {
            value := mload(0x40)
            let abs := add(value, 32)
            mstore(value, size)
            mstore(add(abs, size), 0)
            mstore(0x40, add(abs, and(add(size, 31), not(31))))
        }
    }

    /// @dev Return the unchecked absolute memory address at byte offset i in dst.
    /// The caller must reserve sufficient memory before writing at this position.
    function pos(bytes memory dst, uint i) internal pure returns (uint abs) {
        assembly ("memory-safe") {
            abs := add(add(dst, 32), i)
        }
    }

    /// @dev Remaining length of a validated calldata cursor; ignores metadata.
    function length(uint cur) internal pure returns (uint size) {
        uint abs = uint32(cur);
        unchecked {
            size = uint32(cur >> 32) - abs;
        }
    }

    /// @dev Write a header and return its payload position. Requires size <= uint32.max.
    /// Also overwrites the next 24 bytes: reserve them or use temporary free memory
    /// immediately after a fresh result. Pointer arithmetic is unchecked.
    function writeHeader(uint abs, bytes4 key, uint size) internal pure returns (uint nextAbs) {
        uint keyWord = uint32(key);
        assembly ("memory-safe") {
            mstore(abs, or(shl(224, keyWord), shl(192, size)))
            nextAbs := add(abs, 8)
        }
    }

    /// @dev Write a word to reserved memory and return the position after it.
    function write32(uint abs, bytes32 value) internal pure returns (uint nextAbs) {
        assembly ("memory-safe") {
            mstore(abs, value)
            nextAbs := add(abs, 32)
        }
    }

    /// @dev Copy a memory range and return the next destination. Source and destination
    /// must be valid; composite callers must keep sources disjoint from all writes.
    function copy(uint abs, bytes memory source, uint size) internal pure returns (uint nextAbs) {
        assembly ("memory-safe") {
            mcopy(abs, add(source, 32), size)
            nextAbs := add(abs, size)
        }
    }

    /// @dev Copy a validated absolute calldata range to reserved memory and advance.
    function copy(uint abs, uint sourceAbs, uint size) internal pure returns (uint nextAbs) {
        assembly ("memory-safe") {
            calldatacopy(abs, sourceAbs, size)
            nextAbs := add(abs, size)
        }
    }

    /// @dev Copy all source bytes unchanged, including any existing block header.
    function copy(uint abs, bytes memory source) internal pure returns (uint nextAbs) {
        return copy(abs, source, source.length);
    }

    /// @dev Copy a validated cursor's remaining range unchanged and advance destination.
    function copy(uint abs, uint cur) internal pure returns (uint nextAbs) {
        return copy(abs, uint32(cur), length(cur));
    }

    /// @dev Wrap size memory bytes with a header and advance past the whole block.
    /// Requires size <= payload.length and size <= uint32.max; inherits header
    /// scratch and copy preconditions. Use when the caller already knows the size.
    function wrap(uint abs, bytes4 key, bytes memory payload, uint size) internal pure returns (uint nextAbs) {
        return copy(writeHeader(abs, key, size), payload, size);
    }

    /// @dev Wrap a validated absolute calldata range and advance past the block.
    /// Requires size <= uint32.max; inherits header scratch and copy preconditions.
    function wrap(uint abs, bytes4 key, uint sourceAbs, uint size) internal pure returns (uint nextAbs) {
        return copy(writeHeader(abs, key, size), sourceAbs, size);
    }

    /// @dev Wrap a memory payload with a new header and advance past the whole block.
    /// Inherits writeHeader scratch requirements and copy source/destination preconditions.
    function wrap(uint abs, bytes4 key, bytes memory payload) internal pure returns (uint nextAbs) {
        return wrap(abs, key, payload, payload.length);
    }

    /// @dev Wrap a validated calldata payload cursor with a new header and advance.
    /// Inherits writeHeader scratch requirements and copy source/destination preconditions.
    function wrap(uint abs, bytes4 key, uint cur) internal pure returns (uint nextAbs) {
        return wrap(abs, key, uint32(cur), length(cur));
    }

    // Growable buffers: allocation, initialization, growth, reservation, finalization.

    /// @dev Allocate uninitialized capacity plus one retained scratch word and copy
    /// only the written prefix. Requires written <= capacity <= uint32.max and
    /// written <= dst.length. Unwritten bytes must never be exposed or read.
    function grow(bytes memory dst, uint written, uint capacity) internal pure returns (bytes memory value) {
        assembly ("memory-safe") {
            value := mload(0x40)
            let padded := add(and(add(capacity, 31), not(31)), 32)
            mstore(value, padded)
            mstore(0x40, add(add(value, 32), padded))
            mcopy(add(value, 32), add(dst, 32), written)
        }
    }

    /// @notice Initialize an allocated, growable writer and return its cursor and buffer.
    /// @dev Low 32 bits hold the relative written position; the next 32 hold
    /// logical capacity. Allocate capacity and retained scratch immediately, even for zero
    /// capacity. The returned pair is the only valid starting state for reserve.
    function init(uint capacity) internal pure returns (uint cur, bytes memory dst) {
        if (capacity > type(uint32).max) revert ValueOverflow();
        cur = capacity << 32;
        bytes memory empty;
        dst = grow(empty, 0, capacity);
    }

    /// @dev Cold path, reached only when size exceeds remaining capacity.
    function grow(uint cur, bytes memory dst, uint size) private pure returns (uint nextCur, bytes memory value) {
        uint written = uint32(cur);
        uint capacity = uint32(cur >> 32);
        uint required = written + size;
        if (required > type(uint32).max) revert ValueOverflow();
        unchecked {
            capacity = capacity == 0 ? 64 : capacity * 2;
            while (capacity < required) capacity *= 2;
        }
        if (capacity > type(uint32).max) revert ValueOverflow();
        nextCur = (cur & ~(uint(type(uint32).max) << 32)) | (capacity << 32);
        value = grow(dst, written, capacity);
    }

    /// @notice Reserve size logical bytes and return the updated writer and write address.
    /// @dev Requires a matching allocated pair and position <= capacity. Fill
    /// each reservation before growth/finalization; keep both returned values.
    /// The space check proves advancing cannot carry into the capacity lane.
    /// Metadata above bit 63 is preserved. A retained scratch word permits
    /// header writes without reserving additional logical bytes.
    /// @return nextCur Advanced relative cursor, with updated capacity after growth.
    /// @return value Original or relocated destination; always retain this return.
    /// @return abs Absolute memory address at the beginning of the reservation.
    function reserve(
        uint cur,
        bytes memory dst,
        uint size
    ) internal pure returns (uint nextCur, bytes memory value, uint abs) {
        uint available;
        unchecked {
            available = uint32(cur >> 32) - uint(uint32(cur));
        }
        if (size > available) (cur, dst) = grow(cur, dst, size);
        abs = pos(dst, uint32(cur));
        unchecked {
            nextCur = cur + size;
        }
        value = dst;
    }

    /// @notice Return the written prefix of an initialized writer.
    /// @dev End the writer lifecycle, exposing its initialized prefix and zero
    /// padding. Works in place even when unused; never append after finish.
    function finish(uint cur, bytes memory dst) internal pure returns (bytes memory value) {
        uint written = uint32(cur);
        assembly ("memory-safe") {
            mstore(dst, written)
            mstore(add(add(dst, 32), written), 0)
        }
        value = dst;
    }

    function writeBalance(
        uint cur,
        bytes memory dst,
        bytes32 asset,
        uint amount
    ) internal pure returns (uint nextCur, bytes memory value) {
        uint abs;
        (nextCur, value, abs) = reserve(cur, dst, 72);
        abs = writeHeader(abs, Keys.Balance, 64);
        abs = write32(abs, asset);
        write32(abs, bytes32(amount));
    }

    function writeContext(
        uint cur,
        bytes memory dst,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure returns (uint nextCur, bytes memory value) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint size = 40 + stateSize + inputSize;
        uint abs;
        (nextCur, value, abs) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Context, size - 8);
        }
        abs = write32(abs, account);
        abs = copy(abs, state, stateSize);
        copy(abs, input, inputSize);
    }

    function writeContext(
        uint cur,
        bytes memory dst,
        bytes32 account,
        uint stateCur,
        uint inputCur
    ) internal pure returns (uint nextCur, bytes memory value) {
        uint stateSize = length(stateCur);
        uint inputSize = length(inputCur);
        uint size = 40 + stateSize + inputSize;
        uint abs;
        (nextCur, value, abs) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Context, size - 8);
        }
        abs = write32(abs, account);
        abs = copy(abs, uint32(stateCur), stateSize);
        copy(abs, uint32(inputCur), inputSize);
    }

    function writeContextWrap(
        uint cur,
        bytes memory dst,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure returns (uint nextCur, bytes memory value) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint size = 56 + stateSize + inputSize;
        uint abs;
        (nextCur, value, abs) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Context, size - 8);
        }
        abs = write32(abs, account);
        abs = wrap(abs, Keys.Bytes, state, stateSize);
        wrap(abs, Keys.Bytes, input, inputSize);
    }

    function writeContextWrap(
        uint cur,
        bytes memory dst,
        bytes32 account,
        uint stateCur,
        uint inputCur
    ) internal pure returns (uint nextCur, bytes memory value) {
        uint stateSize = length(stateCur);
        uint inputSize = length(inputCur);
        uint size = 56 + stateSize + inputSize;
        uint abs;
        (nextCur, value, abs) = reserve(cur, dst, size);
        unchecked {
            abs = writeHeader(abs, Keys.Context, size - 8);
        }
        abs = write32(abs, account);
        abs = wrap(abs, Keys.Bytes, uint32(stateCur), stateSize);
        wrap(abs, Keys.Bytes, uint32(inputCur), inputSize);
    }

}
