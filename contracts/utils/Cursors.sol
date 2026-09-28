// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {InvalidBlock, OutOfBounds, UnexpectedPosition, UnconsumedData, ValueOverflow} from "./Errors.sol";

/// @title Cursors
/// @notice Packed forward-only cursor state for source positions.
/// @dev Each cursor uses the following layout:
/// bits  0-31  current source position
/// bits 32-63  source exclusive end
/// bits 64-255 unused; callers supply cursors with zero upper bits.
///
/// For memory buffers, positions are relative to the buffer's zero origin, so
/// the same layout stores the current write offset and logical capacity.
/// Cursor navigation assumes `position <= end`. Constructors establish this
/// invariant and navigation helpers preserve it.
///
/// The zero word represents an absent cursor.
library Cursors {
    // Creation and sources

    /// @notice Pack an already validated absolute range without repeating checks.
    /// @dev Requires abs <= end <= uint32.max. Does not establish calldata provenance.
    function pack(uint abs, uint end) internal pure returns (uint cur) {
        assembly ("memory-safe") { cur := or(abs, shl(32, end)) }
    }

    /// @notice Create a cursor over source range `[abs, end)`.
    /// @param abs Initial absolute source position.
    /// @param end Absolute exclusive end.
    /// @return cur Packed cursor.
    function create(uint abs, uint end) internal pure returns (uint cur) {
        if (abs > end) revert OutOfBounds();
        if (end > type(uint32).max) revert ValueOverflow();
        return pack(abs, end);
    }

    /// @notice Return the absolute calldata position where `source` begins.
    function base(bytes calldata source) internal pure returns (uint abs) {
        assembly ("memory-safe") {
            abs := source.offset
        }
    }

    /// @notice Return the absolute position and exclusive end of `source`.
    function bounds(bytes calldata source) internal pure returns (uint abs, uint end) {
        assembly ("memory-safe") {
            abs := source.offset
            end := add(abs, source.length)
        }
    }

    /// @notice Return absolute bounds for a fixed-stride calldata block stream.
    /// @dev DANGER: Empty streams are valid and `size` must be nonzero. The size
    /// must include the complete block header and payload. Does not validate headers.
    /// @param source Calldata block stream.
    /// @param size Complete encoded size of each block.
    /// @return abs Absolute calldata position of the first block header.
    /// @return end Absolute calldata position immediately after the source.
    function bounds(bytes calldata source, uint size) internal pure returns (uint abs, uint end) {
        uint remainder;
        assembly ("memory-safe") {
            remainder := mod(source.length, size)
            abs := source.offset
            end := add(abs, source.length)
        }
        if (remainder != 0) revert InvalidBlock();
    }

    /// @notice Create a cursor backed by a calldata slice.
    function wrap(bytes calldata source) internal pure returns (uint cur) {
        assembly ("memory-safe") {
            cur := or(source.offset, shl(32, add(source.offset, source.length)))
        }
    }

    // Inspection

    /// @notice Return the cursor's current source position.
    function position(uint cur) internal pure returns (uint abs) {
        return uint32(cur);
    }

    /// @notice Return the cursor's source exclusive end.
    function limit(uint cur) internal pure returns (uint end) {
        return uint32(cur >> 32);
    }

    /// @notice Return the cursor's unread source range.
    function bounds(uint cur) internal pure returns (uint abs, uint end) {
        abs = uint32(cur);
        end = uint32(cur >> 32);
    }

    /// @notice Check fixed-stride divisibility and return a cursor's absolute bounds.
    /// @dev Requires a validated source cursor with current <= end and nonzero size.
    /// Size includes the header. Does not rescan headers, revalidate provenance,
    /// or advance the cursor. Supports fixed-stride execute loops directly.
    function bounds(uint cur, uint size) internal pure returns (uint abs, uint end) {
        uint remainder;
        assembly ("memory-safe") {
            abs := and(cur, 0xffffffff)
            end := and(shr(32, cur), 0xffffffff)
            remainder := mod(sub(end, abs), size)
        }
        if (remainder != 0) revert InvalidBlock();
    }

    /// @notice Return the remaining byte count of a valid cursor.
    /// @dev Requires position <= end; does not validate the source or advance it.
    function length(uint cur) internal pure returns (uint size) {
        unchecked { size = uint32(cur >> 32) - uint(uint32(cur)); }
    }

    /// @notice Return whether the cursor has bytes remaining.
    function more(uint cur) internal pure returns (bool) {
        return uint32(cur) < uint32(cur >> 32);
    }

    /// @notice Return whether the current position equals the exclusive end.
    /// @dev Zero and empty ranges are done; reversed ranges are not.
    function done(uint cur) internal pure returns (bool) {
        return uint32(cur) == uint32(cur >> 32);
    }

    /// @notice Require the cursor to be at source position `abs`.
    function expect(uint cur, uint abs) internal pure {
        if (uint32(cur) != abs) revert UnexpectedPosition();
    }

    /// @notice Require the cursor to be fully consumed.
    /// @dev Reverts UnconsumedData unless position equals end;
    /// neither validates calldata provenance nor changes the cursor.
    function expectEnd(uint cur) internal pure {
        if (!done(cur)) revert UnconsumedData();
    }

    // Navigation

    /// @notice Move the cursor forward to source position `abs`.
    function seek(uint cur, uint abs) internal pure returns (uint nextCur) {
        if (abs < uint32(cur) || abs > uint32(cur >> 32)) revert OutOfBounds();
        nextCur = (cur & ~uint(type(uint32).max)) | abs;
    }

    /// @notice Advance the current position by `amount` bytes.
    function advance(uint cur, uint amount) internal pure returns (uint nextCur) {
        uint abs = uint32(cur);
        uint end = uint32(cur >> 32);
        if (amount > end - abs) revert OutOfBounds();
        // The bound above prevents a carry out of the position lane.
        unchecked { nextCur = cur + amount; }
    }

    /// @notice Replace the cursor's source exclusive end.
    /// @dev Buffer cursors use this as their logical-capacity update.
    function resize(uint cur, uint end) internal pure returns (uint nextCur) {
        if (end > type(uint32).max) revert ValueOverflow();
        if (uint32(cur) > end) revert OutOfBounds();
        nextCur = (cur & ~(uint(type(uint32).max) << 32)) | (end << 32);
    }

    /// @notice Create a child cursor over unread source range `[abs, end)`.
    function slice(uint cur, uint abs, uint end) internal pure returns (uint childCur) {
        if (abs < uint32(cur) || abs > end || end > uint32(cur >> 32)) revert OutOfBounds();
        childCur = abs | (end << 32);
    }

    // Consumption

    /// @notice Mark the remaining range consumed and return the advanced cursor.
    /// @dev Requires a valid cursor. Preserves the end;
    /// performs no validation of skipped bytes or their block structure.
    function exhaust(uint cur) internal pure returns (uint nextCur) {
        return (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
    }

    /// @notice Enter a raw byte range and return its absolute position and the next cursor.
    /// @dev Checks byte containment only; does not inspect a block header or schema.
    /// @return abs Original absolute position.
    /// @return nextCur Cursor after validating and consuming amount bytes.
    function enter(uint cur, uint amount) internal pure returns (uint abs, uint nextCur) {
        abs = uint32(cur);
        nextCur = advance(cur, amount);
    }

    // Calldata conversions. No block headers or schemas are interpreted.

    /// @notice Expose a validated cursor as calldata without copying or advancing.
    /// @dev Requires position <= end <= calldatasize. Zero yields msg.data[0:0].
    function toBytes(uint cur) internal pure returns (bytes calldata data) {
        assembly ("memory-safe") {
            data.offset := and(cur, 0xffffffff)
            data.length := sub(and(shr(32, cur), 0xffffffff), data.offset)
        }
    }

    /// @notice Validate position <= end <= calldatasize, then expose the range.
    /// @dev Reverts OutOfBounds on invalid bounds; zero yields msg.data[0:0].
    function toBytesChecked(uint cur) internal pure returns (bytes calldata data) {
        uint abs = uint32(cur);
        uint end = uint32(cur >> 32);
        if (abs > end || end > msg.data.length) revert OutOfBounds();
        return toBytes(cur);
    }

    /// @notice Expose a validated cursor as a string without UTF-8 validation or copying.
    function toString(uint cur) internal pure returns (string calldata data) {
        return string(toBytes(cur));
    }

}
