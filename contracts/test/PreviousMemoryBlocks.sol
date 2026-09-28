// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Headers} from "../codec/Headers.sol";
import {Position} from "../core/Types.sol";
import {OutOfBounds, ValueOverflow, InvalidBlock} from "../utils/Errors.sol";

/// @title PreviousMemoryBlocks
/// @notice Bounded memory block decoding for local execute commands.
/// @dev Cursors store an absolute memory position in bits 0-31 and exclusive end
/// in bits 32-63. Unpackers preserve higher metadata bits and return nextCur last.
/// Create cursors from live bytes allocations; the layout does not encode the
/// source location, so calldata and memory cursors must not be interchanged.
/// Unlike calldata, memory outside the source has no zero-padding guarantee.
library PreviousMemoryBlocks {

    // Absolute-position primitives. Callers establish containment before reads.

    function read32(uint abs) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            value := mload(abs)
        }
    }

    function expectHeader(uint abs, uint header) private pure {
        if (uint(read32(abs)) >> 192 != header) revert InvalidBlock();
    }

    // Cursor construction and navigation.

    /// @notice Create a cursor over a memory block stream without copying it.
    /// @dev Accepts empty streams; individual unpackers validate block shapes.
    /// The source must be a valid Solidity bytes allocation and remain live.
    /// @param source Encoded blocks in memory.
    /// @return cur Clean cursor with absolute positions and no metadata.
    function cursor(bytes memory source) internal pure returns (uint cur) {
        uint abs;
        assembly ("memory-safe") {
            abs := add(source, 32)
        }
        uint end = abs + source.length;
        if (end > type(uint32).max) revert ValueOverflow();
        cur = abs | (end << 32);
    }

    /// @notice Whether the cursor has unread bytes.
    /// @dev Does not validate the next block or the source allocation.
    function more(uint cur) internal pure returns (bool) {
        return uint32(cur) < uint32(cur >> 32);
    }

    /// @dev Only called with fixed block sizes. Proves containment before any
    /// mload, including for reversed ranges, and prevents carry into the end lane.
    function advance(uint cur, uint size) private pure returns (uint nextCur) {
        unchecked {
            if (uint(uint32(cur)) + size > uint32(cur >> 32)) revert OutOfBounds();
            nextCur = cur + size;
        }
    }

    // Fixed block unpackers.

    /// @notice Decode BALANCE and advance past the complete block.
    /// @dev Checks containment before the exact header, then reads its fields.
    /// @param cur Memory cursor positioned at the block header.
    /// @return asset Balance asset.
    /// @return amount Balance amount.
    /// @return nextCur Advanced cursor preserving its end and metadata.
    function unpackBalance(uint cur) internal pure returns (bytes32 asset, uint amount, uint nextCur) {
        uint abs = uint32(cur);
        nextCur = advance(cur, 72);
        expectHeader(abs, Headers.Balance);
        unchecked {
            asset = read32(abs + 8);
            amount = uint(read32(abs + 40));
        }
    }

    /// @notice Decode POSITION and advance past the complete block.
    /// @dev Checks containment before the exact header, then reads its fields.
    /// @param cur Memory cursor positioned at the block header.
    /// @return asset Position asset.
    /// @return amount Position amount.
    /// @return liability Position liability.
    /// @return debt Position debt.
    /// @return counterparty Position counterparty.
    /// @return nextCur Advanced cursor preserving its end and metadata.
    function unpackPosition(uint cur) internal pure returns (
        bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty, uint nextCur
    ) {
        uint abs = uint32(cur);
        nextCur = advance(cur, 168);
        expectHeader(abs, Headers.Position);
        unchecked {
            asset = read32(abs + 8);
            amount = uint(read32(abs + 40));
            liability = read32(abs + 72);
            debt = uint(read32(abs + 104));
            counterparty = read32(abs + 136);
        }
    }

    /// @notice Decode POSITION into an independent struct and advance the cursor.
    /// @dev The returned struct does not alias the source block; hooks may mutate it.
    /// @param cur Memory cursor positioned at the block header.
    /// @return value Decoded position.
    /// @return nextCur Advanced cursor preserving its end and metadata.
    function unpackPositionValue(uint cur) internal pure returns (Position memory value, uint nextCur) {
        (value.asset, value.amount, value.liability, value.debt, value.counterparty, nextCur) = unpackPosition(cur);
    }
}
