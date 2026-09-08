// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ValueOverflow} from "../utils/Errors.sol";

/// @title Buffers
/// @notice Allocation and finalization helpers for mutable memory byte buffers.
/// @dev `write` copies from memory, while `copy` copies directly from calldata.
library PreviousBufferReserve {
    /// @dev A reserved memory write exceeds the physical backing buffer.
    error BufferOverflow();
    /// @dev A buffer cursor does not match its logical or physical capacity.
    error IncompleteBuffer();

    /// @notice Create a packed buffer cursor at write position zero.
    /// @param len Initial logical byte capacity.
    /// @return cur Packed buffer cursor.
    function cursor(uint len) internal pure returns (uint cur) {
        if (len > type(uint32).max) revert ValueOverflow();
        cur = len << 32;
    }

    /// @notice Reserve relative write space and return the updated packed buffer cursor.
    /// @dev `touch` may exceed `advance` by at most 31 bytes; `alloc` reserves one
    /// trailing word so lazy allocation can safely return without another bounds check.
    /// @param cur Current packed buffer cursor.
    /// @param buffer Current backing buffer.
    /// @param advance Logical number of bytes appended.
    /// @param touch Physical number of bytes the write may touch.
    /// @return updated Updated packed buffer cursor.
    /// @return dst Original or resized backing buffer.
    /// @return i Original write offset.
    function reserve(
        uint cur,
        bytes memory buffer,
        uint advance,
        uint touch
    ) internal pure returns (uint updated, bytes memory dst, uint i) {
        i = uint32(cur);
        uint len = uint32(cur >> 32);
        uint required = i + (advance > touch ? advance : touch);
        bool empty = buffer.length == 0;
        dst = buffer;

        if (required > len) {
            len = len == 0 ? 64 : len * 2;
            while (len < required) {
                len *= 2;
            }
            if (len > type(uint32).max) revert ValueOverflow();
            cur = (cur & ~(uint(type(uint32).max) << 32)) | (len << 32);
            if (!empty) dst = resize(dst, i, len);
        }

        updated = cur + advance;

        if (empty) {
            uint padded = ((len + 31) & ~uint(31)) + 32;
            dst = new bytes(padded);
        }
        if (required > dst.length) revert BufferOverflow();
    }

    /// @notice Allocate a buffer with `capacity` logical bytes and trailing write space.
    /// @dev The returned byte-array length is its padded physical capacity. Callers must
    /// track the logical capacity separately and trim the buffer before returning it.
    /// @param capacity Requested logical byte capacity.
    /// @return buffer Newly allocated padded buffer.
    function alloc(uint capacity) internal pure returns (bytes memory buffer) {
        uint padded = ((capacity + 31) & ~uint(31)) + 32;
        buffer = new bytes(padded);
    }

    /// @notice Allocate a buffer with `capacity` and copy its written prefix.
    /// @dev Performs no bounds checks; the caller must ensure `written <= buffer.length`.
    /// @param buffer Current buffer.
    /// @param written Number of leading bytes to copy.
    /// @param capacity Requested capacity of the new buffer.
    /// @return resized Newly allocated buffer containing the written prefix.
    function resize(bytes memory buffer, uint written, uint capacity) internal pure returns (bytes memory resized) {
        uint padded = ((capacity + 31) & ~uint(31)) + 32;
        resized = new bytes(padded);
        assembly ("memory-safe") {
            mcopy(add(resized, 0x20), add(buffer, 0x20), written)
        }
    }

    /// @notice Write raw bytes at byte offset `i`.
    /// @param buffer Destination buffer.
    /// @param i Destination byte offset.
    /// @param value Bytes to copy.
    /// @return next Position immediately after the copied bytes.
    function write(bytes memory buffer, uint i, bytes memory value) internal pure returns (uint next) {
        next = i + value.length;
        if (next > buffer.length) revert BufferOverflow();
        assembly ("memory-safe") {
            mcopy(add(add(buffer, 0x20), i), add(value, 0x20), mload(value))
        }
    }

    /// @notice Copy raw calldata bytes to byte offset `i`.
    /// @param buffer Destination buffer.
    /// @param i Destination byte offset.
    /// @param value Calldata bytes to copy.
    /// @return next Position immediately after the copied bytes.
    function copy(bytes memory buffer, uint i, bytes calldata value) internal pure returns (uint next) {
        next = i + value.length;
        if (next > buffer.length) revert BufferOverflow();
        assembly ("memory-safe") {
            calldatacopy(add(add(buffer, 0x20), i), value.offset, value.length)
        }
    }

    /// @notice Write one complete raw word at byte offset `i`.
    /// @param buffer Destination buffer.
    /// @param i Destination byte offset.
    /// @param value Word to write.
    function write32(bytes memory buffer, uint i, bytes32 value) internal pure {
        if (i + 32 > buffer.length) revert BufferOverflow();
        assembly ("memory-safe") {
            mstore(add(add(buffer, 0x20), i), value)
        }
    }

    /// @notice Write two complete raw words at byte offset `i`.
    /// @param buffer Destination buffer.
    /// @param i Destination byte offset.
    /// @param a First word to write.
    /// @param b Second word to write.
    function write64(bytes memory buffer, uint i, bytes32 a, bytes32 b) internal pure {
        if (i + 64 > buffer.length) revert BufferOverflow();
        assembly ("memory-safe") {
            let p := add(add(buffer, 0x20), i)
            mstore(p, a)
            mstore(add(p, 0x20), b)
        }
    }

    /// @notice Write three complete raw words at byte offset `i`.
    /// @param buffer Destination buffer.
    /// @param i Destination byte offset.
    /// @param a First word to write.
    /// @param b Second word to write.
    /// @param c Third word to write.
    function write96(bytes memory buffer, uint i, bytes32 a, bytes32 b, bytes32 c) internal pure {
        if (i + 96 > buffer.length) revert BufferOverflow();
        assembly ("memory-safe") {
            let p := add(add(buffer, 0x20), i)
            mstore(p, a)
            mstore(add(p, 0x20), b)
            mstore(add(p, 0x40), c)
        }
    }

    /// @notice Set a buffer's visible length to the number of bytes actually written.
    /// @param buffer Buffer to trim in place.
    /// @param len Logical byte length to expose.
    /// @return The same buffer with its length set to `len`.
    function trim(bytes memory buffer, uint len) internal pure returns (bytes memory) {
        if (len > buffer.length) revert BufferOverflow();
        assembly ("memory-safe") {
            mstore(buffer, len)
        }
        return buffer;
    }

    /// @notice Return an empty buffer when unused, otherwise trim it to the cursor position.
    /// @param cur Packed buffer cursor.
    /// @param buffer Backing byte buffer.
    /// @return out Empty bytes when unused, otherwise the written prefix.
    function finish(uint cur, bytes memory buffer) internal pure returns (bytes memory out) {
        uint i = uint32(cur);
        uint len = uint32(cur >> 32);
        if (i == 0) return new bytes(0);
        if (i > len || i > buffer.length) revert IncompleteBuffer();
        assembly ("memory-safe") {
            mstore(buffer, i)
        }
        out = buffer;
    }
}
