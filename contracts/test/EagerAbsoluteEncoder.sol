// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder} from "../codec/Encoder.sol";
import {Keys} from "../codec/Keys.sol";
import {ValueOverflow} from "../utils/Errors.sol";

/// @dev Test-only eager absolute writer. Always allocated; low32 is current
/// memory address, next32 is capacity end. Retains Encoder scratch rules.
library EagerAbsoluteEncoder {
    /// @dev Allocate capacity and retained scratch immediately. Both cursor
    /// addresses must fit uint32; no sentinel or deferred hint representation.
    function init(uint capacity) internal pure returns (uint cur, bytes memory dst) {
        uint base;
        assembly ("memory-safe") { base := add(mload(0x40), 32) }
        uint end = base + capacity;
        if (end > type(uint32).max) revert ValueOverflow();
        bytes memory empty;
        dst = Encoder.grow(empty, 0, capacity);
        cur = base | (end << 32);
    }
    /// @dev Cold path: recover relative lengths, relocate, and rebuild addresses.
    function grow(uint cur, bytes memory dst, uint size) private pure returns (uint nextCur, bytes memory value) {
        uint base = Encoder.pos(dst, 0);
        uint written;
        uint capacity;
        unchecked {
            written = uint32(cur) - base;
            capacity = uint32(cur >> 32) - base;
        }
        uint required = written + size;
        if (required > type(uint32).max) revert ValueOverflow();
        unchecked {
            capacity = capacity == 0 ? 64 : capacity * 2;
            while (capacity < required) capacity *= 2;
        }
        (nextCur, value) = init(capacity);
        Encoder.copy(uint32(nextCur), dst, written);
        unchecked { nextCur = (cur & ~uint(type(uint64).max)) | (nextCur + written); }
    }
    /// @dev Requires the matching allocated pair and base <= position <= end.
    /// Fill every reservation before growth/finalization. Retain both returns;
    /// previously saved absolute write addresses become stale on relocation.
    function reserve(uint cur, bytes memory dst, uint size) internal pure returns (uint nextCur, bytes memory value, uint abs) {
        uint available;
        unchecked { available = uint32(cur >> 32) - uint(uint32(cur)); }
        if (size > available) (cur, dst) = grow(cur, dst, size);
        abs = uint32(cur);
        unchecked { nextCur = cur + size; }
        value = dst;
    }
    /// @dev Expose the initialized prefix and clear padding, including when empty.
    /// Ends the writer lifecycle; do not append after finish.
    function finish(uint cur, bytes memory dst) internal pure returns (bytes memory value) {
        uint abs = uint32(cur);
        assembly ("memory-safe") {
            mstore(dst, sub(abs, add(dst, 32)))
            mstore(abs, 0)
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
