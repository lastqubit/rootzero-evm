// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {PreviousNamingEncoder} from "./PreviousNaming.sol";

import {Keys, ACCOUNT_BALANCE_KEY} from "../codec/Keys.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Actions} from "./PreviousActions.sol";
import {Entities} from "./PreviousEntities.sol";
import {States} from "./PreviousStates.sol";
import {Cursors} from "../utils/Cursors.sol";

/// @notice Emit structured logs from encoded memory, calldata or scalar values.
/// @dev Address-based stream helpers require caller-owned writable prefix memory.
// Frozen pre-category event encoding for historical benchmarks.
library Logs {
    /// @dev Endpoint log word: low uint32 flags, followed by seven ordered uint32 codes.
    /// Lane constants include Enabled. Combine lanes with ONE semantic preset;
    /// semantic identifiers sharing a slot must never be OR-ed together.
    uint internal constant Enabled = 1;
    uint internal constant State = Enabled | 2;
    uint internal constant Input = Enabled | 4;
    uint internal constant Output = Enabled | 8;

    // Host metadata and recovery.
    uint internal constant Unresolved = Enabled | ((Entities.Host | (States.Unresolved << 32)) << 32);
    uint internal constant Resolved = Enabled | ((Entities.Host | (States.Resolved << 32)) << 32);
    uint internal constant Introduce = Enabled | ((Entities.Host | (Actions.Introduce << 32)) << 32);
    uint internal constant Register = Enabled | ((Entities.Host | (Actions.Add << 32)) << 32);
    uint internal constant Annotate = Enabled | ((Entities.Host | (Actions.Annotate << 32)) << 32);

    // Host access and configuration.
    uint internal constant Authorize = Enabled | ((Entities.Host | (Actions.Authorize << 32) | (States.Active << 64)) << 32);
    uint internal constant Revoke = Enabled | ((Entities.Host | (Actions.Revoke << 32) | (States.Inactive << 64)) << 32);
    uint internal constant Appoint = Enabled | ((Entities.Host | (Entities.Guardian << 32) | (Actions.Appoint << 64) | (States.Active << 96)) << 32);
    uint internal constant Dismiss = Enabled | ((Entities.Host | (Entities.Guardian << 32) | (Actions.Dismiss << 64) | (States.Inactive << 96)) << 32);
    uint internal constant Update = Enabled | ((Entities.Host | (Actions.Update << 32)) << 32);
    uint internal constant AllowAsset = Enabled | ((Entities.Host | (Actions.Allow << 32) | (States.Active << 64)) << 32);
    uint internal constant DenyAsset = Enabled | ((Entities.Host | (Actions.Deny << 32) | (States.Inactive << 64)) << 32);
    uint internal constant AddPool = Enabled | ((Entities.Host | (Entities.Pool << 32) | (Actions.Add << 64)) << 32);
    uint internal constant RemovePool = Enabled | ((Entities.Host | (Entities.Pool << 32) | (Actions.Remove << 64)) << 32);

    // Asset metadata and account operations.
    uint internal constant AssetAnnotate = Enabled | ((Entities.Asset | (Actions.Annotate << 32)) << 32);
    uint internal constant Balance = Enabled | ((Entities.Account | (Actions.Update << 32)) << 32);
    uint internal constant Payout = Enabled | ((Entities.Account | (Actions.Payout << 32)) << 32);
    uint internal constant Deposit = Enabled | ((Entities.Account | (Actions.Deposit << 32)) << 32);
    uint internal constant Withdraw = Enabled | ((Entities.Account | (Actions.Withdraw << 32)) << 32);
    uint internal constant Cashout = Enabled | ((Entities.Account | (Actions.Cashout << 32)) << 32);
    uint internal constant Burn = Enabled | ((Entities.Account | (Actions.Burn << 32)) << 32);
    uint internal constant Realize = Enabled | ((Entities.Account | (Actions.Realize << 32)) << 32);
    uint internal constant Swap = Enabled | (Actions.Swap << 32);

    /// @notice Extract the raw code list for standalone event prefixes.
    function codes(uint logs) internal pure returns (uint) { return logs >> 32; }

    /// @notice Emit a command account and one memory-backed lane after processing.
    /// @dev For adapters with no returned output. Uses temporary free memory;
    /// accepts any valid bytes allocation, without requiring owned prefix space.
    function accountWrap(uint id, bytes32 account, bytes4 key, bytes memory value) internal {
        uint size = value.length;
        uint start;
        assembly ("memory-safe") { start := mload(0x40) }
        uint abs = Encoder.write32(start, bytes32(id));
        abs = Encoder.write32(abs, account);
        Encoder.wrap(abs, key, value);
        assembly ("memory-safe") { log0(start, add(size, 72)) }
    }

    /// @notice Emit a command account and one calldata-backed lane after processing.
    /// @dev Caller supplies a validated cursor; no persistent allocation is made.
    function accountWrap(uint id, bytes32 account, bytes4 key, uint cur) internal {
        uint size = Encoder.length(cur);
        uint start;
        assembly ("memory-safe") { start := mload(0x40) }
        uint abs = Encoder.write32(start, bytes32(id));
        abs = Encoder.write32(abs, account);
        Encoder.wrap(abs, key, cur);
        assembly ("memory-safe") { log0(start, add(size, 72)) }
    }
    // Correlation stream identifier.
    uint internal constant Stream = 0x00;

    /// @dev Raw assembly form of Logs.Balance: Account followed by Update.
    uint private constant ACCOUNT_UPDATE_CODES = 0x0000000220000001;

    // Memory streams.

    /// @notice Emit codes followed by an existing memory block stream using LOG0.
    /// @dev Caller owns initialized memory [abs, abs + size) containing a complete
    /// valid block stream and the writable word [abs - 32, abs). Empty streams are
    /// allowed but still require that word. abs >= 32; size + 32 and abs + size
    /// must not overflow. All addressed memory must be valid; no checks are performed.
    /// Saves the preceding word, writes codes, logs, then restores the word exactly.
    /// Preserves payload, neighboring memory and free-memory pointer. No allocation,
    /// copying or persistent scratch writes. Reacquire addresses after buffer growth.
    /// @param rawCodes Full uint256 code word, emitted unchanged without a format tag.
    /// @param abs Absolute memory address of the first block header (or empty range
    /// start), not a calldata cursor, relative offset, bytes length word or struct pointer.
    /// @param size Initialized stream length in bytes, including block headers but
    /// excluding the codes prefix, unused capacity and padding. For active writers,
    /// use the written length rather than the buffer's capacity.
    function mem(uint rawCodes, uint abs, uint size) internal {
        assembly ("memory-safe") {
            let start := sub(abs, 32)
            let saved := mload(start)
            mstore(start, rawCodes)
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

    /// @notice Copy a memory stream into one block and emit prefix plus block using LOG0.
    /// @dev Accepts any live Solidity bytes allocation; no writable prefix is required.
    /// Caller validates the payload and supplies its key; length must fit uint32.
    /// Uses temporary memory [F, F + 40 + length), where F is the free-memory pointer.
    /// The range must be available without overflow. Preserves the source, other
    /// allocated memory and free-memory pointer; scratch contents are unspecified.
    /// No bounds or framing checks. Empty streams still emit the block header.
    function memCopyWrap(uint prefix, bytes4 key, bytes memory value) internal {
        uint keyValue = uint32(key);
        assembly ("memory-safe") {
            let start := mload(0x40)
            let size := mload(value)
            mstore(add(start, 8), or(shl(32, keyValue), size))
            mstore(start, prefix)
            mcopy(add(start, 40), add(value, 32), size)
            log0(start, add(size, 40))
        }
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

    // Calldata streams.

    /// @notice Copy a calldata block stream to temporary memory and emit codes plus it using LOG0.
    /// @dev Caller guarantees abs <= calldatasize() and size <= calldatasize() - abs,
    /// and that the range contains a complete valid block stream; empty streams are
    /// allowed. No bounds, block-framing or code validation is performed. Out-of-range
    /// calldata would be zero-filled by CALLDATACOPY rather than rejected.
    /// Uses temporary memory [F, F + 32 + size), where F is the free-memory pointer
    /// on entry. size + 32 and F + 32 + size must not overflow; that memory must be
    /// available for temporary use. Preserves allocated memory and free-memory pointer;
    /// temporary contents are unspecified afterward. No persistent allocation or padding.
    /// @param rawCodes Full uint256 code word, emitted unchanged without a format tag.
    /// @param abs Absolute calldata byte offset of the first block header (or empty
    /// range start), not a packed calldata cursor, relative offset or memory address.
    /// @param size Stream length in bytes, including block headers but excluding any
    /// ABI offset/length wrapper, the codes prefix and calldata outside the selected range.
    function copy(uint rawCodes, uint abs, uint size) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore(start, rawCodes)
            calldatacopy(add(start, 32), abs, size)
            log0(start, add(size, 32))
        }
    }

    /// @notice Copy a calldata cursor's unread block stream and emit codes plus it using LOG0.
    /// @dev Requires a valid calldata range containing complete blocks, with position <= end.
    /// The absolute-range overload's temporary-memory requirements apply. No bounds or
    /// block validation is performed. Preserves the cursor and free-memory pointer.
    /// @param rawCodes Full uint256 code word, emitted unchanged without a format tag.
    /// @param cur Packed calldata cursor: position in bits 0-31, exclusive end in
    /// bits 32-63; higher metadata bits are ignored. Zero emits codes alone.
    function copy(uint rawCodes, uint cur) internal {
        copy(rawCodes, Cursors.position(cur), Cursors.length(cur));
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

    /// @notice Wrap a calldata cursor's unread payload and emit prefix plus block using LOG0.
    /// @dev Requires a valid calldata range with position <= end. Inherits the
    /// absolute-range overload's payload and temporary-memory requirements.
    /// No bounds or framing checks. Higher cursor metadata bits are ignored.
    /// Preserves the cursor and free-memory pointer. Zero emits an empty block.
    function copyWrap(uint prefix, bytes4 key, uint cur) internal {
        copyWrap(prefix, key, Cursors.position(cur), Cursors.length(cur));
    }

    // Scalar values.

    /// @notice Emit codes followed by one ENVELOPE block using LOG0.
    /// @dev Allocates through Encoder and emits exactly 168 bytes without topics.
    /// Caller supplies scope and Relay/Dispatch action codes and establishes the
    /// corresponding host/account identity. Does not send a message or verify fields.
    /// @param portal Destination portal host ID.
    /// @param resources Chain-specific resources assigned to the operation.
    /// @param key Transport correlation or recovery lookup key, independent of digest.
    /// @param digest Keccak256 of the exact forwarded payload bytes, not the envelope.
    /// @param rawCodes Full-width scope/action codes, emitted unchanged.
    function envelope(uint portal, uint resources, bytes32 key, bytes32 digest, uint rawCodes) internal {
        bytes memory data = Encoder.createEnvelope(portal, resources, key, digest);
        mem(rawCodes, Encoder.pos(data, 0), data.length);
    }

    /// @notice Emit codes followed by one RESOLUTION block using LOG0.
    /// @dev Allocates through Encoder and emits exactly 104 bytes without topics.
    /// The emitter identifies the host; key and digest identify the recovery record.
    /// This helper performs no storage mutation, witness validation or recovery.
    function resolution(bytes32 key, bytes32 digest, uint rawCodes) internal {
        bytes memory data = Encoder.createResolution(key, digest);
        mem(rawCodes, Encoder.pos(data, 0), data.length);
    }

    /// @notice Emit codes followed by one INTRODUCTION block using LOG0.
    /// @dev Allocates through Encoder and emits 136 bytes without topics. The emitter
    /// identifies the receiving host. Caller validates peer identity; origin and
    /// blocknum are provenance and a claim, not authorization or verified deployment data.
    function introduction(uint peer, bytes32 origin, uint blocknum, uint rawCodes) internal {
        bytes memory data = Encoder.createIntroduction(peer, origin, blocknum);
        mem(rawCodes, Encoder.pos(data, 0), data.length);
    }

    /// @notice Emit codes followed by one ENDPOINT block using LOG0.
    /// @dev Allocates through Encoder; preserves the ID and all three pure lane specs; logCodes defaults to zero.
    /// Emits 200 bytes with no topics. The emitter identifies the publishing host.
    function endpoint(uint id, uint state, uint input, uint output, uint rawCodes) internal {
        endpoint(id, state, input, output, 0, rawCodes);
    }

    /// @notice Publish endpoint specs and its single execution-log code word.
    function endpoint(uint id, uint state, uint input, uint output, uint logCodes, uint rawCodes) internal {
        bytes memory data = Encoder.allocate(168);
        uint abs = Encoder.writeHeader(Encoder.pos(data, 0), bytes4(keccak256("#endpoint")), 160);
        abs = Encoder.write32(abs, bytes32(id));
        abs = Encoder.write32(abs, bytes32(state));
        abs = Encoder.write32(abs, bytes32(input));
        abs = Encoder.write32(abs, bytes32(output));
        Encoder.write32(abs, bytes32(logCodes));
        mem(rawCodes, Encoder.pos(data, 0), data.length);
    }

    /// @notice Create and emit an ANNOTATION block preceded by codes using LOG0.
    /// @dev Accepts ordinary memory bytes; allocates the complete block through Encoder.
    /// The caller supplies an encoded annotation stream and its scope codes. This
    /// helper preserves entity and data without interpreting or validating claims.
    /// Each annotation type defines its own identity, merge and revocation rules.
    function annotation(uint entity, bytes memory data, uint rawCodes) internal {
        bytes memory value = PreviousNamingEncoder.createAnnotation(entity, data);
        mem(rawCodes, Encoder.pos(value, 0), value.length);
    }

    /// @notice Create and emit a PIPELINE block preceded by codes using LOG0.
    /// @dev Uses 104 temporary bytes at the free-memory pointer without advancing it.
    /// Preserves allocated memory; scratch contents are unspecified. Emits 104 bytes:
    /// codes plus a PIPELINE block. No existing writer or owned prefix is required.
    /// No extra format tag or topics. The caller defines pipeline scope and emission
    /// timing; this helper does not authorize the account, enforce expiry or move value.
    /// @dev Convention: nested pipelines preserve the account. Implementations that
    /// change it must log switches and restoration explicitly. Pipeline.pipe calls this
    /// helper at entry. The initial budget is not additive across nested calls.
    /// @param account Account used by this pipeline and its nested pipelines.
    /// @param budget Initial native-value budget for this invocation, in the chain's native unit.
    /// @param rawCodes Full uint256 descriptive code word, emitted unchanged.
    function pipeline(bytes32 account, uint budget, uint rawCodes) internal {
        uint key = uint32(Keys.Pipeline);
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore(start, rawCodes)
            mstore(add(start, 32), or(shl(224, key), shl(192, 64)))
            mstore(add(start, 40), account)
            mstore(add(start, 72), budget)
            log0(start, 104)
        }
    }

    /// @notice Emit an authoritative actual account balance using fixed Account/Update codes.
    /// @dev Emits [AccountUpdate:32][ACCOUNT_BALANCE:104] through LOG0. Uses 136
    /// temporary bytes at the free-memory pointer without advancing it or touching
    /// live allocations. Call after a successful nonzero credit/debit, including
    /// a resulting zero balance. Implementers own emission; this helper does not
    /// mutate storage. Indexers replace the balance, never apply it as a delta.
    /// @param account Account whose balance changed.
    /// @param asset Asset identifier.
    /// @param amount Actual updated balance, preferably the mutation's computed result.
    function balance(bytes32 account, bytes32 asset, uint amount) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore(start, ACCOUNT_UPDATE_CODES)
            mstore(add(start, 32), or(shl(224, ACCOUNT_BALANCE_KEY), shl(192, 96)))
            mstore(add(start, 40), account)
            mstore(add(start, 72), asset)
            mstore(add(start, 104), amount)
            log0(start, 136)
        }
    }
}
