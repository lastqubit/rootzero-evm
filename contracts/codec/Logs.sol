// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Encoder} from "./Encoder.sol";
import {Cursors} from "../utils/Cursors.sol";

/// @notice Emit structured logs from encoded memory, calldata or scalar values.
/// @dev Address-based stream helpers require caller-owned writable prefix memory.
library Logs {
    // Correlation stream identifier.
    uint internal constant Stream = 0x00;

    /// @notice Emit codes followed by an existing memory block stream using LOG0.
    /// @dev Caller owns initialized memory [abs, abs + size) containing a complete
    /// valid block stream and the writable word [abs - 32, abs). Empty streams are
    /// allowed but still require that word. abs >= 32; size + 32 and abs + size
    /// must not overflow. All addressed memory must be valid; no checks are performed.
    /// Saves the preceding word, writes codes, logs, then restores the word exactly.
    /// Preserves payload, neighboring memory and free-memory pointer. No allocation,
    /// copying or persistent scratch writes. Reacquire addresses after buffer growth.
    /// @param codes Full uint256 code word, emitted unchanged without a format tag.
    /// @param abs Absolute memory address of the first block header (or empty range
    /// start), not a calldata cursor, relative offset, bytes length word or struct pointer.
    /// @param size Initialized stream length in bytes, including block headers but
    /// excluding the codes prefix, unused capacity and padding. For active writers,
    /// use the written length rather than the buffer's capacity.
    function mem(uint codes, uint abs, uint size) internal {
        assembly ("memory-safe") {
            let start := sub(abs, 32)
            let saved := mload(start)
            mstore(start, codes)
            log0(start, add(size, 32))
            mstore(start, saved)
        }
    }

    /// @notice Emit a prefix and a wrapped memory stream without copying its payload.
    /// @dev Requires a finished bytes value from Encoder.allocate/init/grow, with
    /// its owned leading word and length <= uint32.max. Do not pass arbitrary
    /// bytes values or an unfinished writer. Temporarily overwrites the length
    /// and part of the leading word; restores both exactly after LOG0. Preserves
    /// payload, padding and free-memory pointer. Empty streams retain the header.
    function memWrap(uint prefix, bytes4 key, bytes memory value) internal {
        uint keyValue = uint32(key);
        assembly ("memory-safe") {
            let preceding := sub(value, 32)
            let saved := mload(preceding)
            let size := mload(value)
            mstore(value, or(shl(32, keyValue), size))
            mstore(sub(value, 8), prefix)
            log0(sub(value, 8), add(size, 40))
            mstore(preceding, saved)
            mstore(value, size)
        }
    }

    /// @notice Copy a calldata block stream to temporary memory and emit codes plus it using LOG0.
    /// @dev Caller guarantees abs <= calldatasize() and size <= calldatasize() - abs,
    /// and that the range contains a complete valid block stream; empty streams are
    /// allowed. No bounds, block-framing or code validation is performed. Out-of-range
    /// calldata would be zero-filled by CALLDATACOPY rather than rejected.
    /// Uses temporary memory [F, F + 32 + size), where F is the free-memory pointer
    /// on entry. size + 32 and F + 32 + size must not overflow; that memory must be
    /// available for temporary use. Preserves allocated memory and free-memory pointer;
    /// temporary contents are unspecified afterward. No persistent allocation or padding.
    /// @param codes Full uint256 code word, emitted unchanged without a format tag.
    /// @param abs Absolute calldata byte offset of the first block header (or empty
    /// range start), not a packed calldata cursor, relative offset or memory address.
    /// @param size Stream length in bytes, including block headers but excluding any
    /// ABI offset/length wrapper, the codes prefix and calldata outside the selected range.
    function copy(uint codes, uint abs, uint size) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore(start, codes)
            calldatacopy(add(start, 32), abs, size)
            log0(start, add(size, 32))
        }
    }

    /// @notice Wrap a calldata range in one block and emit prefix plus block using LOG0.
    /// @dev Requires a valid calldata range and size <= uint32.max. Caller supplies
    /// the correct key and validates the payload. Uses temporary memory
    /// [F, F + 40 + size); preserves allocated memory and the free-memory pointer.
    /// As with copy, no bounds or framing checks are performed. Empty payloads
    /// still emit the eight-byte block header. The prefix is emitted unchanged.
    function copyWrap(uint prefix, bytes4 key, uint abs, uint size) internal {
        uint keyValue = uint32(key);
        assembly ("memory-safe") {
            let start := mload(0x40)
            // Write the right-aligned header first, then overwrite its leading
            // scratch bytes with the prefix. No trailing scratch word is needed.
            mstore(add(start, 8), or(shl(32, keyValue), size))
            mstore(start, prefix)
            calldatacopy(add(start, 40), abs, size)
            log0(start, add(size, 40))
        }
    }

    /// @notice Copy a calldata cursor's unread block stream and emit codes plus it using LOG0.
    /// @dev Requires a valid calldata range containing complete blocks, with position <= end.
    /// The absolute-range overload's temporary-memory requirements apply. No bounds or
    /// block validation is performed. Preserves the cursor and free-memory pointer.
    /// @param codes Full uint256 code word, emitted unchanged without a format tag.
    /// @param cur Packed calldata cursor: position in bits 0-31, exclusive end in
    /// bits 32-63; higher metadata bits are ignored. Zero emits codes alone.
    function copy(uint codes, uint cur) internal {
        copy(codes, Cursors.position(cur), Cursors.length(cur));
    }

    /// @notice Emit a tagged correlation ID followed by an existing block stream using LOG0.
    /// @dev Caller owns the initialized range [abs, abs + size)
    /// and the writable word [abs - 32, abs). The range must contain a
    /// complete valid block stream; zero size is allowed but still needs the preceding word.
    /// abs >= 32, size + 32 and abs + size must not overflow.
    /// All addressed memory must be valid. No range, framing or ID checks are performed.
    /// Saves the preceding word, replaces it with correlationId, logs, then restores it
    /// exactly. Preserves the stream, neighboring memory and free-memory pointer;
    /// no allocation, copying or persistent scratch writes occur.
    /// A bytes payload can use its length word as the prefix. For an active Encoder
    /// buffer, use the initialized written length, not capacity, and reacquire the
    /// address after any growth. No active writer is required for this helper.
    /// @param correlationId Complete bytes32 ID whose highest byte MUST equal Stream
    /// (0x00). Emitted unchanged; the tag is part of the ID, not an extra byte.
    /// @param abs Absolute memory address of the first block's 8-byte header
    /// (or the empty range start), not a calldata cursor, buffer offset or struct pointer.
    /// @param size Initialized stream length in bytes, including all block headers
    /// but excluding the preceding correlation-ID word and any unused capacity or padding.
    function stream(bytes32 correlationId, uint abs, uint size) internal {
        mem(uint(correlationId), abs, size);
    }

    /// @notice Create and emit a ROOTED block preceded by codes using LOG0.
    /// @dev Allocates through Encoder and logs through mem; no existing writer or
    /// caller-managed memory is required. Emits 136 bytes: codes plus a ROOTED block.
    /// No extra format tag or topics. The caller defines pipeline scope and emission
    /// timing; this helper does not authorize the account, enforce expiry or move value.
    /// @param account Account establishing the root pipeline context.
    /// @param deadline Full-width expiry timestamp, encoded unchanged.
    /// @param value Full-width native value in the emitting chain's native unit.
    /// @param codes Full uint256 descriptive code word, emitted unchanged.
    function rooted(bytes32 account, uint deadline, uint value, uint codes) internal {
        bytes memory data = Encoder.createRooted(account, deadline, value);
        mem(codes, Encoder.pos(data, 0), data.length);
    }

    /// @notice Create and emit one full-width BALANCE block preceded by codes using LOG0.
    /// @dev Allocates the block through Encoder and logs it through mem. No existing
    /// writer, memory prefix or pointer is required. Emits 104 bytes: 32-byte codes
    /// followed by the 72-byte BALANCE block, with no topics or additional format tag.
    /// Emits no account. The emitter defines whether amount is a delta or a resulting balance.
    /// @param asset Full-width asset identifier, encoded unchanged.
    /// @param amount Full-width quantity, encoded unchanged.
    /// @param codes Full uint256 descriptive code word, emitted unchanged.
    function balance(bytes32 asset, uint amount, uint codes) internal {
        bytes memory data = Encoder.createBalance(asset, amount);
        mem(codes, Encoder.pos(data, 0), data.length);
    }

}
