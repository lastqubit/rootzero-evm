// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Encoder} from "../codec/Encoder.sol";
import {Keys} from "../codec/Keys.sol";
import {ValueOverflow} from "../utils/Errors.sol";

/// @dev Test-only absolute-memory alternative. Once allocated, low32 is the
/// write address and next32 is the capacity end address. Before allocation only,
/// low32 == 0 is a sentinel and next32 holds the lazy capacity hint.
/// Sources, initialized-prefix, scratch, and lifecycle rules match Encoder.
library AbsoluteEncoderBuffer {
    function grow(uint cur, bytes memory dst, uint size) private pure returns (uint nextCur, bytes memory value) {
        uint abs = uint32(cur);
        uint capacity = uint32(cur >> 32);
        uint written;
        if (abs != 0) {
            uint base = Encoder.pos(dst, 0);
            unchecked {
                written = abs - base;
                capacity -= base;
            }
        }
        uint required = written + size;
        if (required > capacity) {
            if (required > type(uint32).max) revert ValueOverflow();
            unchecked {
                capacity = capacity == 0 ? 64 : capacity * 2;
                while (capacity < required) capacity *= 2;
            }
        }
        uint base;
        assembly ("memory-safe") { base := add(mload(0x40), 64) }
        uint end = base + capacity;
        if (end > type(uint32).max) revert ValueOverflow();
        value = Encoder.grow(dst, written, capacity);
        unchecked { nextCur = (cur & ~uint(type(uint64).max)) | (end << 32) | (base + written); }
    }

    function reserve(uint cur, bytes memory dst, uint size) internal pure returns (uint nextCur, bytes memory value, uint abs) {
        abs = uint32(cur);
        uint required = abs + size;
        if (abs == 0 || required > uint32(cur >> 32)) {
            (cur, dst) = grow(cur, dst, size);
            abs = uint32(cur);
        }
        unchecked { nextCur = cur + size; }
        value = dst;
    }

    function finish(uint cur, bytes memory dst) internal pure returns (bytes memory value) {
        uint abs = uint32(cur);
        if (abs == 0) return new bytes(0);
        uint written;
        unchecked { written = abs - Encoder.pos(dst, 0); }
        if (written == 0) return new bytes(0);
        assembly ("memory-safe") {
            mstore(dst, written)
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

    /// @notice Append CONTEXT by copying complete validated memory STATE and INPUT children.
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

    /// @notice Append CONTEXT by copying complete validated calldata STATE and INPUT children.
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

    /// @notice Append CONTEXT by wrapping memory payloads in STATE and INPUT headers.
    /// @dev Inherits reserve and the bytes-first writeContextWrap source requirements.
    function writeContextWrap(uint cur, bytes memory dst, bytes32 account, bytes memory state, bytes memory input) internal pure returns (uint nextCur, bytes memory value) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint size = 56 + stateSize + inputSize;
        uint abs;
        (nextCur, value, abs) = reserve(cur, dst, size);
        unchecked { abs = Encoder.writeHeader(abs, Keys.Context, size - 8); }
        abs = Encoder.write32(abs, account);
        abs = Encoder.wrap(abs, Keys.State, state, stateSize);
        Encoder.wrap(abs, Keys.Input, input, inputSize);
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
        abs = Encoder.wrap(abs, Keys.State, uint32(stateCur), stateSize);
        Encoder.wrap(abs, Keys.Input, uint32(inputCur), inputSize);
    }

}
