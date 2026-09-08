// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {OutOfBounds, UnexpectedPosition, ValueOverflow} from "./Errors.sol";

/// @notice Mutable memory wrapper around a packed cursor.
struct Cur {
    uint state;
}

/// @title Cursors
/// @notice Packed forward-only cursor state for source positions.
/// @dev Each cursor uses the following layout:
/// bits  0-31  current source position
/// bits 32-63  source exclusive end
/// bits 64-71  flags (consumer-defined)
///
/// For memory buffers, positions are relative to the buffer's zero origin, so
/// the same layout stores the current write offset and logical capacity.
/// Cursor navigation assumes `position <= end`. Constructors establish this
/// invariant and navigation helpers preserve it.
///
/// The zero word represents an absent cursor.
library Cursors {
    // Creation and sources

    /// @notice Create a cursor over source range `[pos, end)`.
    /// @param pos Initial source position.
    /// @param end Source exclusive end.
    /// @param flags Consumer-defined flags.
    /// @return cur Packed cursor.
    function create(uint pos, uint end, uint8 flags) internal pure returns (uint cur) {
        if (pos > end) revert OutOfBounds();
        if (end > type(uint32).max) revert ValueOverflow();
        cur = pos | (end << 32) | (uint(flags) << 64);
    }

    /// @notice Return the absolute calldata position where `source` begins.
    function base(bytes calldata source) internal pure returns (uint abs) {
        assembly ("memory-safe") {
            abs := source.offset
        }
    }

    /// @notice Return the absolute start and exclusive end of `source`.
    function bounds(bytes calldata source) internal pure returns (uint abs, uint end) {
        assembly ("memory-safe") {
            abs := source.offset
            end := add(abs, source.length)
        }
    }

    /// @notice Return the cursor's unread source range.
    function bounds(uint cur) internal pure returns (uint pos, uint end) {
        pos = uint32(cur);
        end = uint32(cur >> 32);
    }

    /// @notice Return the unread calldata region represented by the cursor.
    /// @dev DANGER: This trusts the packed cursor and does not validate its
    /// bounds against `msg.data`.
    function raw(uint cur) internal pure returns (bytes calldata data) {
        assembly ("memory-safe") {
            data.offset := and(cur, 0xffffffff)
            data.length := sub(and(shr(32, cur), 0xffffffff), data.offset)
        }
    }

    /// @notice Create a cursor backed by a calldata slice.
    function wrap(bytes calldata source) internal pure returns (uint cur) {
        assembly ("memory-safe") {
            cur := or(source.offset, shl(32, add(source.offset, source.length)))
        }
    }

    // Inspection

    /// @notice Return the cursor's current source position.
    function position(uint cur) internal pure returns (uint) {
        return uint32(cur);
    }

    /// @notice Return the cursor's source exclusive end.
    function limit(uint cur) internal pure returns (uint) {
        return uint32(cur >> 32);
    }

    /// @notice Return whether the cursor has bytes remaining.
    function more(uint cur) internal pure returns (bool) {
        return uint32(cur) < uint32(cur >> 32);
    }

    /// @notice Require the cursor to be at source position `pos`.
    function expect(uint cur, uint pos) internal pure {
        if (uint32(cur) != pos) revert UnexpectedPosition();
    }

    /// @notice Return whether the cursor contains `flag`.
    function flagged(uint cur, uint8 flag) internal pure returns (bool) {
        return uint8(cur >> 64) & flag != 0;
    }

    // Navigation

    /// @notice Move the cursor forward to source position `pos`.
    function seek(uint cur, uint pos) internal pure returns (uint updated) {
        if (pos < uint32(cur) || pos > uint32(cur >> 32)) revert OutOfBounds();
        updated = (cur & ~uint(type(uint32).max)) | pos;
    }

    /// @notice Advance the current position by `amount` bytes.
    function advance(uint cur, uint amount) internal pure returns (uint updated) {
        uint pos = uint32(cur);
        uint end = uint32(cur >> 32);
        if (amount > end - pos) revert OutOfBounds();
        // The bound above prevents a carry out of the position lane.
        unchecked { updated = cur + amount; }
    }

    /// @notice Replace the cursor's source exclusive end.
    /// @dev Buffer cursors use this as their logical-capacity update.
    function resize(uint cur, uint end) internal pure returns (uint updated) {
        if (end > type(uint32).max) revert ValueOverflow();
        if (uint32(cur) > end) revert OutOfBounds();
        updated = (cur & ~(uint(type(uint32).max) << 32)) | (end << 32);
    }

    /// @notice Create a child cursor over unread source range `[start, end)`.
    function slice(uint cur, uint start, uint end) internal pure returns (uint child) {
        if (start < uint32(cur) || start > end || end > uint32(cur >> 32)) revert OutOfBounds();
        child = start | (end << 32);
    }

    // Consumption

    /// @notice Return the current source position and advance by `amount`.
    function consume(uint cur, uint amount) internal pure returns (uint updated, uint abs) {
        abs = uint32(cur);
        uint end = uint32(cur >> 32);
        if (amount > end - abs) revert OutOfBounds();
        // The bound above prevents a carry out of the position lane.
        unchecked { updated = cur + amount; }
    }
}
