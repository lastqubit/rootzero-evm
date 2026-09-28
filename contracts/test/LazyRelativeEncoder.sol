// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder} from "../codec/Encoder.sol";
import {Keys} from "../codec/Keys.sol";
import {ValueOverflow} from "../utils/Errors.sol";
/// @dev Frozen lazy lifecycle baseline for eager allocation benchmarks.
library LazyRelativeEncoder {
    // Growable buffers: initialization, allocation/growth, reservation, finalization.

    /// @notice Initialize a growable writer without allocating its buffer.
    /// @dev Low 32 bits hold the written position; the next 32 hold capacity.
    /// Start with an empty bytes buffer. All buffers can grow; capacity is a hint.
    function init(uint capacity) internal pure returns (uint cur) {
        if (capacity > type(uint32).max) revert ValueOverflow();
        cur = capacity << 32;
    }

    /// @dev Slow reservation path: choose geometric capacity, allocate, and retain
    /// the written prefix. Called only when capacity or backing memory is missing.
    function grow(uint cur, bytes memory dst, uint required) private pure returns (uint nextCur, bytes memory value) {
        uint capacity = uint32(cur >> 32);
        if (required > capacity) {
            if (required > type(uint32).max) revert ValueOverflow();
            unchecked {
                capacity = capacity == 0 ? 64 : capacity * 2;
                while (capacity < required) capacity *= 2;
            }
            if (capacity > type(uint32).max) revert ValueOverflow();
            cur = (cur & ~(uint(type(uint32).max) << 32)) | (capacity << 32);
        }
        nextCur = cur;
        value = Encoder.grow(dst, uint32(cur), capacity);
    }

    /// @notice Reserve size logical bytes, growing the buffer when needed.
    /// @dev Use only matching cursors/buffers maintained by these helpers. Fill
    /// every reserved byte before growth or finish; do not mutate dst.length.
    /// Preserves cursor metadata above bit 63. Allocations retain at least 32
    /// scratch bytes beyond capacity, so header writes need no extra reservation.
    /// Always retain both returned cur and dst: growth can relocate the buffer.
    /// @return nextCur Cursor advanced by size, with the possibly increased capacity.
    /// @return value Original or relocated buffer.
    /// @return abs Absolute memory position at the start of the reserved range.
    function reserve(uint cur, bytes memory dst, uint size) internal pure returns (uint nextCur, bytes memory value, uint abs) {
        uint written = uint32(cur);
        uint required = written + size;
        if (required > uint32(cur >> 32) || dst.length == 0) {
            (cur, dst) = grow(cur, dst, required);
        }
        unchecked { nextCur = cur + size; }
        value = dst;
        abs = Encoder.pos(dst, written);
    }

    /// @notice Finalize a writer, exposing exactly its written bytes with zero padding.
    /// @dev Requires a matching buffer/cursor from these helpers and all reserved
    /// bytes initialized. Finishes the writer lifecycle; do not append afterward.
    function finish(uint cur, bytes memory dst) internal pure returns (bytes memory value) {
        uint written = uint32(cur);
        if (written == 0) return new bytes(0);
        assembly ("memory-safe") {
            mstore(dst, written)
            mstore(add(add(dst, 32), written), 0)
        }
        value = dst;
    }

    // Cursor writers: reserve and write, returning both updated cursor and buffer.

    /// @notice Append BALANCE to a growable writer and return its updated state.
    /// @dev Inherits reserve's writer lifecycle requirements.
    function writeBalance(uint cur, bytes memory dst, bytes32 asset, uint amount) internal pure returns (uint nextCur, bytes memory value) {
        uint abs;
        (nextCur, value, abs) = reserve(cur, dst, 72);
        abs = Encoder.writeHeader(abs, Keys.Balance, 64);
        abs = Encoder.write32(abs, asset);
        Encoder.write32(abs, bytes32(amount));
    }

    /// @notice Append CONTEXT by copying complete validated memory BYTES children.
    /// @dev Inherits reserve and the bytes-first writeContext source requirements.
    function writeContext(uint cur, bytes memory dst, bytes32 account, bytes memory state, bytes memory input) internal pure returns (uint nextCur, bytes memory value) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint size = 40 + stateSize + inputSize;
        uint abs;
        (nextCur, value, abs) = reserve(cur, dst, size);
        unchecked { abs = Encoder.writeHeader(abs, Keys.Context, size - 8); }
        abs = Encoder.write32(abs, account);
        abs = Encoder.copy(abs, state, stateSize);
        Encoder.copy(abs, input, inputSize);
    }

    /// @notice Append CONTEXT by copying complete validated calldata BYTES children.
    /// @dev Inherits reserve and the bytes-first writeContext source requirements.
    function writeContext(uint cur, bytes memory dst, bytes32 account, uint stateCur, uint inputCur) internal pure returns (uint nextCur, bytes memory value) {
        uint stateSize = Encoder.length(stateCur);
        uint inputSize = Encoder.length(inputCur);
        uint size = 40 + stateSize + inputSize;
        uint abs;
        (nextCur, value, abs) = reserve(cur, dst, size);
        unchecked { abs = Encoder.writeHeader(abs, Keys.Context, size - 8); }
        abs = Encoder.write32(abs, account);
        abs = Encoder.copy(abs, uint32(stateCur), stateSize);
        Encoder.copy(abs, uint32(inputCur), inputSize);
    }

    /// @notice Append CONTEXT by wrapping memory payloads in BYTES headers.
    /// @dev Inherits reserve and the bytes-first writeContextWrap source requirements.
    function writeContextWrap(uint cur, bytes memory dst, bytes32 account, bytes memory state, bytes memory input) internal pure returns (uint nextCur, bytes memory value) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint size = 56 + stateSize + inputSize;
        uint abs;
        (nextCur, value, abs) = reserve(cur, dst, size);
        unchecked { abs = Encoder.writeHeader(abs, Keys.Context, size - 8); }
        abs = Encoder.write32(abs, account);
        abs = Encoder.wrap(abs, Keys.Bytes, state, stateSize);
        Encoder.wrap(abs, Keys.Bytes, input, inputSize);
    }

    /// @notice Append CONTEXT by wrapping validated calldata payload cursors.
    /// @dev Inherits reserve and the bytes-first writeContextWrap source requirements.
    function writeContextWrap(uint cur, bytes memory dst, bytes32 account, uint stateCur, uint inputCur) internal pure returns (uint nextCur, bytes memory value) {
        uint stateSize = Encoder.length(stateCur);
        uint inputSize = Encoder.length(inputCur);
        uint size = 56 + stateSize + inputSize;
        uint abs;
        (nextCur, value, abs) = reserve(cur, dst, size);
        unchecked { abs = Encoder.writeHeader(abs, Keys.Context, size - 8); }
        abs = Encoder.write32(abs, account);
        abs = Encoder.wrap(abs, Keys.Bytes, uint32(stateCur), stateSize);
        Encoder.wrap(abs, Keys.Bytes, uint32(inputCur), inputSize);
    }

}
