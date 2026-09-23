// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {Buffers} from "../codec/Buffers.sol";
import {Sizes, Specs, Headers} from "../codec/Specs.sol";
import {Cursors, Cur} from "../utils/Cursors.sol";
import {InsufficientValue, OutOfBounds, UnexpectedPosition, UnconsumedData} from "../utils/Errors.sol";
import {Budget} from "../core/Budget.sol";
import {Calls} from "../core/Calls.sol";
import {
    AssetAmount,
    AssetLiability,
    AccountAsset,
    HostAsset,
    AccountAmount,
    HostAmount,
    HostAccountAsset,
    Quote, Position,
    Tx
} from "../core/Types.sol";

/// @notice Mutable state shared across one endpoint execution.
/// @dev `decoders` stores input current/end in bits 0-63 and state current/end
/// in bits 64-127 (32 bits per position). Bits 128 and 129 record declared state and input lanes.
/// Remaining bits are reserved; this is not a generic cursor.
struct Execution {
    bytes32 account;
    uint budget;
    uint decoders;
    uint writer;
    bytes output;
}

/// @title Executions
/// @notice Opening, decoding, output, and value helpers for executions.
/// @dev `output*` helpers consume memory inputs; `outputCopy*` helpers copy
/// calldata inputs directly to the output stream.
library Executions {
    // -------------------------------------------------------------------------
    // Description and opening
    // -------------------------------------------------------------------------

    /// @notice Describe an endpoint's schemas, allocation metadata, and behavior.
    /// @dev Layout: [state key:4][input key:4][output key:4][source key:4]
    /// [source block size:4][output block size:4][source shift:1][lanes:1][reserved:5][flags:1].
    /// Source shift: 64 = state, 0 = input or none. Sizes include headers.
    /// Lane bits: 0 = state declared, 1 = input declared; copied into decoder bits 128-135.
    /// Declared state takes precedence over input, including when supplied state is empty.
    function describe(uint state, uint input, uint output, uint8 flags) internal pure returns (uint descriptor) {
        uint32 stateKey = uint32(Specs.key(state));
        uint32 inputKey = uint32(Specs.key(input));
        uint source = stateKey != 0 ? state : input;
        descriptor |= uint(stateKey) << 224;
        descriptor |= uint(inputKey) << 192;
        descriptor |= uint(uint32(Specs.key(output))) << 160;
        descriptor |= uint(uint32(Specs.key(source))) << 128;
        descriptor |= Specs.blockSize(source) << 96;
        descriptor |= Specs.blockSize(output) << 64;
        descriptor |= uint(stateKey != 0 ? 64 : 0) << 56;
        descriptor |= uint((stateKey != 0 ? 1 : 0) | (inputKey != 0 ? 2 : 0)) << 48;
        descriptor |= flags;
    }

    /// @dev Capacity is only a hint; decoding validates the stream and buffers can grow.
    function writerCursor(uint decoders, uint descriptor) private pure returns (uint writer) {
        if (uint32(descriptor >> 160) == 0) return 0;
        uint count = 1;
        bytes4 key = bytes4(uint32(descriptor >> 128));
        if (key != bytes4(0)) {
            uint source = decoders >> uint8(descriptor >> 56);
            uint abs = uint32(source);
            uint end = uint32(source >> 32);
            uint blockSize = uint32(descriptor >> 96);
            if (blockSize != 0 && (end - abs) % blockSize == 0) {
                count = (end - abs) / blockSize;
            } else {
                count = Blocks.runCount(abs, end, key);
            }
        }
        writer = Buffers.cursor(count * uint32(descriptor >> 64));
    }

    /// @notice Open an execution containing only the current call-value budget.
    /// @dev Decoders, writer, and output remain empty.
    /// @return exec Budget-only execution initialized with `msg.value`.
    function open() internal view returns (Execution memory exec) {
        exec.budget = msg.value;
    }

    /// @notice Initialize an input-only execution and its native-value budget.
    /// @dev `exec` must be newly allocated or otherwise empty.
    /// @param exec Execution to initialize.
    /// @param descriptor Packed endpoint descriptor.
    /// @param budget Initial native-value budget.
    /// @param input Descriptor-backed input source.
    function openInput(Execution memory exec, uint descriptor, uint budget, bytes calldata input) internal pure {
        uint decoders;
        assembly ("memory-safe") {
            decoders := or(
                or(input.offset, shl(32, add(input.offset, input.length))),
                shl(128, and(byte(25, descriptor), 2))
            )
        }
        exec.budget = budget;
        exec.decoders = decoders;
        exec.writer = writerCursor(decoders, descriptor);
    }

    /// @notice Initialize a complete command execution from its context and descriptor-backed sources.
    /// @dev `exec` must be newly allocated or otherwise empty. Input always
    /// occupies bits 0-63 and state bits 64-127.
    /// @param exec Execution to initialize.
    /// @param descriptor Packed command descriptor.
    /// @param account Command account.
    /// @param budget Initial native-value budget.
    /// @param state Descriptor-backed state source.
    /// @param input Descriptor-backed input source.
    function open(
        Execution memory exec,
        uint descriptor,
        bytes32 account,
        uint budget,
        bytes calldata state,
        bytes calldata input
    ) internal pure {
        uint decoders;
        assembly ("memory-safe") {
            decoders := or(
                or(input.offset, shl(32, add(input.offset, input.length))),
                or(shl(64, or(state.offset, shl(32, add(state.offset, state.length)))), shl(128, byte(25, descriptor)))
            )
        }
        exec.account = account;
        exec.budget = budget;
        exec.decoders = decoders;
        exec.writer = writerCursor(decoders, descriptor);
    }

    // -------------------------------------------------------------------------
    // Traversal
    // -------------------------------------------------------------------------

    // Source inspection

    /// @notice Return whether either execution source has blocks remaining.
    /// @param exec Execution to inspect.
    /// @return Whether either decoder source has unread bytes.
    function more(Execution memory exec) internal pure returns (bool) {
        uint decoders = exec.decoders;
        return uint32(decoders) < uint32(decoders >> 32) || uint32(decoders >> 64) < uint32(decoders >> 96);
    }

    /// @notice Return the input decoder's current absolute calldata position.
    function absolute(Execution memory exec) internal pure returns (uint) {
        return uint32(exec.decoders);
    }

    // Raw source access

    /// @notice Return the unread bounded command state without consuming it.
    function rawState(Execution memory exec) internal pure returns (bytes calldata data) {
        uint decoders = exec.decoders;
        if ((decoders & (1 << 128)) == 0) return msg.data[0:0];
        uint current = uint32(decoders >> 64);
        uint end = uint32(decoders >> 96);
        if (end > msg.data.length || current > end) revert Blocks.MalformedBlocks();
        // The explicit checks above already prove this slice is in calldata.
        assembly ("memory-safe") {
            data.offset := current
            data.length := sub(end, current)
        }
    }

    /// @notice Return the unread state source and mark it fully consumed.
    /// @dev Intended for commands that forward their remaining state without decoding it.
    /// A state source declared EMPTY is returned empty and remains unconsumed so close
    /// still rejects any state supplied against the descriptor.
    function takeRawState(Execution memory exec) internal pure returns (bytes calldata data) {
        data = rawState(exec);
        if ((exec.decoders & (1 << 128)) == 0) return data;
        // rawState already validated current <= end <= calldatasize.
        uint decoders = exec.decoders;
        exec.decoders = (decoders & ~(uint(type(uint32).max) << 64))
            | (uint(uint32(decoders >> 96)) << 64);
    }

    /// @notice Validate and consume the unread state as zero or more BALANCE blocks.
    /// @dev Checks every block's key and fixed payload size without re-encoding it.
    /// Like rawState, an EMPTY source remains unconsumed for close to reject.
    /// @return data Original calldata containing the validated BALANCE stream.
    function takeRawBalances(Execution memory exec) internal pure returns (bytes calldata data) {
        data = rawState(exec);
        // Empty and undeclared lanes require neither scanning nor cursor mutation.
        if (data.length == 0) return data;
        uint abs;
        uint end;
        assembly ("memory-safe") { abs := data.offset end := add(abs, data.length) }
        uint64 expected = Headers.Balance;
        while (abs < end) {
            // Check each remaining block before its header, matching unpackBalance's
            // error order even when an earlier bad key precedes a truncated tail.
            unchecked { if (end - abs < Sizes.Balance) revert OutOfBounds(); }
            uint64 head;
            assembly ("memory-safe") { head := shr(192, calldataload(abs)) }
            if (head != expected) revert Blocks.InvalidBlock();
            unchecked { abs += Sizes.Balance; }
        }
        uint decoders = exec.decoders;
        exec.decoders = (decoders & ~(uint(type(uint32).max) << 64)) | (end << 64);
    }

    /// @notice Return the unread bounded endpoint input without consuming it.
    function rawInput(Execution memory exec) internal pure returns (bytes calldata data) {
        uint decoders = exec.decoders;
        if ((decoders & (1 << 129)) == 0) return msg.data[0:0];
        uint current = uint32(decoders);
        uint end = uint32(decoders >> 32);
        if (end > msg.data.length || current > end) revert Blocks.MalformedBlocks();
        // The explicit checks above already prove this slice is in calldata.
        assembly ("memory-safe") {
            data.offset := current
            data.length := sub(end, current)
        }
    }

    /// @notice Return the unread input source and mark it fully consumed.
    /// @dev Intended for endpoints that forward their remaining input without decoding it.
    /// An input source declared EMPTY is returned empty and remains unconsumed so close
    /// still rejects any input supplied against the descriptor.
    function takeRawInput(Execution memory exec) internal pure returns (bytes calldata data) {
        data = rawInput(exec);
        if ((exec.decoders & (1 << 129)) == 0) return data;
        // rawInput already validated current <= end <= calldatasize.
        uint decoders = exec.decoders;
        exec.decoders = (decoders & ~uint(type(uint32).max)) | uint32(decoders >> 32);
    }

    // Block traversal

    /// @notice Return whether the next input block has `key` and an empty payload.
    /// @param exec Execution whose input cursor is inspected without advancing.
    /// @param key Expected block key.
    /// @return Whether a complete matching empty block header occurs next.
    function isEmpty(Execution memory exec, bytes4 key) internal pure returns (bool) {
        uint decoders = exec.decoders;
        return Blocks.isEmpty(uint32(decoders), uint32(decoders >> 32), key);
    }

    /// @notice Consume a matching empty input block when present.
    /// @param exec Execution whose input cursor advances only for a matching empty block.
    /// @param key Expected block key.
    /// @return Whether an empty block was consumed.
    function tryConsumeEmpty(Execution memory exec, bytes4 key) internal pure returns (bool) {
        uint decoders = exec.decoders;
        uint abs = uint32(decoders);
        uint limit = uint32(decoders >> 32);
        (bytes4 current, uint len) = Blocks.peek(abs, limit);
        if (current != key || len != 0) return false;
        uint next = abs + Sizes.Header;
        seekInput(exec, next);
        return true;
    }

    /// @notice Validate and consume the next block from execution input.
    /// @param exec Execution whose input cursor is advanced over the complete block.
    /// @param spec Expected block specification.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function consume(Execution memory exec, uint spec) internal pure returns (uint body, uint end) {
        uint current = uint32(exec.decoders);
        (body, end) = Blocks.enter(current, spec);
        seekInput(exec, end);
    }

    /// @notice Validate a known key and consume the next block from execution input.
    /// @dev Validates no payload-size constraint beyond proving the complete block
    /// lies within the input source's logical region.
    /// @param exec Execution whose input cursor is advanced over the complete block.
    /// @param key Expected block key.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function consume(Execution memory exec, bytes4 key) internal pure returns (uint body, uint end) {
        uint current = uint32(exec.decoders);
        (body, end) = Blocks.enter(current, key);
        seekInput(exec, end);
    }

    /// @notice Validate and consume one input block, returning its complete encoding.
    /// @param exec Execution whose input cursor is advanced past the block.
    /// @param key Expected block key.
    /// @return data Calldata view of the complete block, including its header.
    function takeBlock(Execution memory exec, bytes4 key) internal pure returns (bytes calldata data) {
        (uint abs, uint end) = consume(exec, key);
        data = msg.data[abs - Sizes.Header:end];
    }

    /// @notice Validate and enter the payload of the next execution input block.
    /// @dev The input cursor remains in its existing frame so callers can decode
    /// child blocks in place. Callers should prove complete payload consumption
    /// with `exec.expect(end)` after decoding the children from input.
    /// Entry advances a uint32 cursor by a header and optional uint32-bounded
    /// payload prefix, so it cannot move backward or overflow uint256. The upper
    /// input-bound check also ensures the new position still fits uint32.
    /// @param exec Execution whose input cursor advances over the block header.
    /// @param spec Expected parent block specification.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function enter(Execution memory exec, uint spec) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        (body, end) = Blocks.enter(uint32(decoders), spec);
        if (body > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | body;
    }

    /// @notice Validate and enter the payload of the next keyed execution input block.
    /// @dev Validates no payload-size constraint. Callers should prove complete
    /// payload consumption with `exec.expect(end)` after decoding.
    /// @param exec Execution whose input cursor advances over the block header.
    /// @param key Expected parent block key.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function enter(Execution memory exec, bytes4 key) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        (body, end) = Blocks.enter(uint32(decoders), key);
        if (body > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | body;
    }

    /// @notice Validate a parent block and advance over a fixed payload prefix.
    /// @dev `amount` is relative to the payload start and cannot exceed the
    /// current parent payload. The returned `abs` remains the payload start.
    /// @param exec Execution whose input cursor advances over the header and fixed prefix.
    /// @param spec Expected parent block specification.
    /// @param amount Number of initial payload bytes to advance over.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function enter(Execution memory exec, uint spec, uint amount) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        uint next;
        (body, next, end) = Blocks.enter(uint32(decoders), spec, amount);
        if (next > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | next;
    }

    /// @notice Validate a keyed parent block and advance over a fixed payload prefix.
    /// @dev Validates no payload-size constraint beyond the requested prefix.
    /// The returned `body` remains the payload start.
    /// @param exec Execution whose input cursor advances over the header and fixed prefix.
    /// @param key Expected parent block key.
    /// @param amount Number of initial payload bytes to advance over.
    /// @return body Absolute position of the first payload byte.
    /// @return end Absolute position immediately after the payload.
    function enter(Execution memory exec, bytes4 key, uint amount) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        uint next;
        (body, next, end) = Blocks.enter(uint32(decoders), key, amount);
        if (next > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | next;
    }

    // Raw input navigation

    /// @notice Advance execution input by a raw byte count.
    /// @dev No block header or schema is validated.
    /// @param exec Execution whose input cursor is advanced.
    /// @param amount Number of bytes to advance.
    function advance(Execution memory exec, uint amount) internal pure {
        take(exec, amount);
    }

    /// @notice Take a raw byte range from execution input.
    /// @dev No block header or schema is validated.
    /// @param exec Execution whose input cursor is advanced.
    /// @param amount Number of bytes to take.
    /// @return abs Absolute position of the first taken byte.
    function take(Execution memory exec, uint amount) internal pure returns (uint abs) {
        uint decoders = exec.decoders;
        abs = uint32(decoders);
        uint end = uint32(decoders >> 32);
        if (amount > end - abs) revert OutOfBounds();
        unchecked {
            exec.decoders = decoders + amount;
        }
    }

    /// @notice Require the active execution decoder to be at absolute position `abs`.
    /// @param exec Execution whose input position is validated.
    /// @param abs Expected absolute position.
    function expect(Execution memory exec, uint abs) internal pure {
        if (uint32(exec.decoders) != abs) revert UnexpectedPosition();
    }

    // Scoped input traversal

    /// @notice Consume a LIST block and return a cursor scoped to its payload.
    /// @param exec Execution whose input cursor is advanced.
    /// @return items Cursor over the nested list items.
    function list(Execution memory exec) internal pure returns (Cur memory items) {
        return list(exec, Specs.List);
    }

    /// @notice Consume a list block described by `spec` and return a cursor scoped to its payload.
    /// @param exec Execution whose input cursor is advanced.
    /// @param spec Custom list block specification.
    /// @return items Cursor over the nested list items.
    function list(Execution memory exec, uint spec) internal pure returns (Cur memory items) {
        (uint abs, uint end) = consume(exec, spec);
        items.state = Cursors.create(abs, end, 0);
    }

    // Specialized cursor mutation

    /// @dev Advance the specialized state cursor and return its previous absolute position.
    function takeState(Execution memory exec, uint amount) private pure returns (uint abs) {
        uint decoders = exec.decoders;
        abs = uint32(decoders >> 64);
        uint end = uint32(decoders >> 96);
        if (amount > end - abs) revert OutOfBounds();
        unchecked {
            exec.decoders = decoders + (amount << 64);
        }
    }

    /// @dev Move the specialized input cursor to a validated absolute position.
    function seekInput(Execution memory exec, uint next) private pure {
        // Every caller derives next from a uint32 position plus a header
        // and bounded payload. It cannot move backward or overflow uint256.
        uint decoders = exec.decoders;
        uint end = uint32(decoders >> 32);
        if (next > end) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | next;
    }

    // -------------------------------------------------------------------------
    // Fixed-width block decoding
    // -------------------------------------------------------------------------

    /// @dev Return the next raw calldata word from input and advance by `size` bytes.
    function nextN(Execution memory exec, uint size) private pure returns (bytes32 value) {
        value = Blocks.read32(take(exec, size));
    }

    /// @notice Return the next raw input byte and advance by one byte.
    function next1(Execution memory exec) internal pure returns (bytes1 value) {
        value = bytes1(nextN(exec, 1));
    }

    /// @notice Return the next two raw input bytes and advance by two bytes.
    function next2(Execution memory exec) internal pure returns (bytes2 value) {
        value = bytes2(nextN(exec, 2));
    }

    /// @notice Return the next four raw input bytes and advance by four bytes.
    function next4(Execution memory exec) internal pure returns (bytes4 value) {
        value = bytes4(nextN(exec, 4));
    }

    /// @notice Return the next eight raw input bytes and advance by eight bytes.
    function next8(Execution memory exec) internal pure returns (bytes8 value) {
        value = bytes8(nextN(exec, 8));
    }

    /// @notice Return the next sixteen raw input bytes and advance by sixteen bytes.
    function next16(Execution memory exec) internal pure returns (bytes16 value) {
        value = bytes16(nextN(exec, 16));
    }

    /// @notice Return the next raw calldata word from input and advance it.
    /// @param exec Execution whose input cursor advances by one word.
    /// @return value Raw word at the input cursor's previous position.
    function next32(Execution memory exec) internal pure returns (bytes32 value) {
        value = nextN(exec, Sizes.Word);
    }

    /// @notice Decode one fixed 32-byte payload from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @param spec Expected fixed block specification.
    /// @return value Decoded payload word.
    function unpack32(Execution memory exec, uint spec) internal pure returns (bytes32 value) {
        uint abs = take(exec, Sizes.B32);
        uint64 head;
        assembly ("memory-safe") { head := shr(192, calldataload(abs)) }
        if (head != ((uint64(uint32(Specs.key(spec))) << 32) | 32)) revert Blocks.InvalidBlock();
        assembly ("memory-safe") {
            value := calldataload(add(abs, 0x08))
        }
    }

    /// @notice Decode and consume one ACCOUNT block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return account Decoded account identifier.
    function unpackAccount(Execution memory exec) internal pure returns (bytes32 account) {
        uint abs = take(exec, Sizes.B32);
        account = Blocks.unpackAccount(abs);
    }

    /// @notice Decode and consume one NODE block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return node Decoded node identifier.
    function unpackNode(Execution memory exec) internal pure returns (uint node) {
        uint abs = take(exec, Sizes.B32);
        node = Blocks.unpackNode(abs);
    }

    /// @notice Decode and consume one BOOTSTRAP block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded balance amount.
    /// @return budget Decoded native-value budget contribution.
    function unpackBootstrap(Execution memory exec) internal pure returns (bytes32 asset, uint amount, uint budget) {
        uint abs = take(exec, Sizes.Bootstrap);
        return Blocks.unpackBootstrap(abs);
    }

    /// @notice Decode and consume one ASSET block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return asset Decoded asset identifier.
    function unpackAsset(Execution memory exec) internal pure returns (bytes32 asset) {
        uint abs = take(exec, Sizes.B32);
        asset = Blocks.unpackAsset(abs);
    }

    /// @notice Decode and consume one LIMITS block.
    /// @return limits Packed minimum asset amount (high 128 bits) and maximum debt (low 128 bits).
    function unpackLimits(Execution memory exec) internal pure returns (uint limits) {
        uint abs = take(exec, Sizes.Limits);
        limits = Blocks.unpackLimits(abs);
    }

    /// @notice Consume one LIMITS input and check final quantities directly against calldata.
    /// @param exec Execution whose input cursor is bounded and advanced by one block.
    /// @param amount Final asset amount, checked against the inclusive minimum.
    /// @param debt Final debt, checked against the literal inclusive maximum.
    function requireLimits(Execution memory exec, uint amount, uint debt) internal pure {
        uint abs = take(exec, Sizes.Limits);
        Blocks.requireLimits(abs, amount, debt);
    }

    /// @notice Decode and consume one QUOTE input with minimum amount and maximum debt.
    function unpackQuote(
        Execution memory exec
    ) internal pure returns (bytes32 asset, bytes32 liability, bytes32 counterparty, uint limits) {
        uint abs = take(exec, Sizes.Quote);
        (asset, liability, counterparty, limits) = Blocks.unpackQuote(abs);
    }

    /// @notice Decode one QUOTE into its structured value.
    function unpackQuoteValue(Execution memory exec) internal pure returns (Quote memory quote) {
        (quote.asset, quote.liability, quote.counterparty, quote.limits) = unpackQuote(exec);
    }

    /// @notice Decode and consume one ASSET_LIABILITY block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return asset Decoded asset identifier.
    /// @return liability Decoded liability identifier.
    function unpackAssetLiability(Execution memory exec) internal pure returns (bytes32 asset, bytes32 liability) {
        uint abs = take(exec, Sizes.B64);
        (asset, liability) = Blocks.unpackAssetLiability(abs);
    }

    /// @notice Decode one ASSET_LIABILITY block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded asset and liability pair.
    function unpackAssetLiabilityValue(Execution memory exec) internal pure returns (AssetLiability memory value) {
        (value.asset, value.liability) = unpackAssetLiability(exec);
    }

    /// @notice Decode and consume one ACCOUNT_ASSET block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    function unpackAccountAsset(Execution memory exec) internal pure returns (bytes32 account, bytes32 asset) {
        uint abs = take(exec, Sizes.B64);
        (account, asset) = Blocks.unpackAccountAsset(abs);
    }

    /// @notice Decode one ACCOUNT_ASSET block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded account and asset.
    function unpackAccountAssetValue(Execution memory exec) internal pure returns (AccountAsset memory value) {
        (value.account, value.asset) = unpackAccountAsset(exec);
    }

    /// @notice Decode and consume one HOST_ASSET block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    function unpackHostAsset(Execution memory exec) internal pure returns (uint host, bytes32 asset) {
        uint abs = take(exec, Sizes.HostAsset);
        (host, asset) = Blocks.unpackHostAsset(abs);
    }

    /// @notice Decode one HOST_ASSET block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded host and asset.
    function unpackHostAssetValue(Execution memory exec) internal pure returns (HostAsset memory value) {
        (value.host, value.asset) = unpackHostAsset(exec);
    }

    /// @notice Decode and consume one AMOUNT block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackAmount(Execution memory exec) internal pure returns (bytes32 asset, uint amount) {
        uint abs = take(exec, Sizes.Amount);
        (asset, amount) = Blocks.unpackAmount(abs);
    }

    /// @notice Decode one AMOUNT block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded asset and amount.
    function unpackAmountValue(Execution memory exec) internal pure returns (AssetAmount memory value) {
        (value.asset, value.amount) = unpackAmount(exec);
    }

    // Dedicated state block decoding

    /// @notice Decode and consume one BALANCE block from state.
    /// @param exec Execution whose state cursor is advanced.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded balance amount.
    function unpackBalance(Execution memory exec) internal pure returns (bytes32 asset, uint amount) {
        uint abs = takeState(exec, Sizes.Balance);
        (asset, amount) = Blocks.unpackBalance(abs);
    }

    /// @notice Decode and consume one BALANCE block from state into its structured value.
    /// @param exec Execution whose state cursor is advanced.
    /// @return value Decoded asset and balance amount.
    function unpackBalanceValue(Execution memory exec) internal pure returns (AssetAmount memory value) {
        (value.asset, value.amount) = unpackBalance(exec);
    }

    /// @notice Decode and consume one CUSTODY block from state.
    /// @param exec Execution whose state cursor is advanced.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded custody amount.
    function unpackCustody(Execution memory exec) internal pure returns (uint host, bytes32 asset, uint amount) {
        uint abs = takeState(exec, Sizes.Custody);
        (host, asset, amount) = Blocks.unpackCustody(abs);
    }

    /// @notice Decode and consume one CUSTODY block from state into its structured value.
    /// @param exec Execution whose state cursor is advanced.
    /// @return value Decoded host, asset, and custody amount.
    function unpackCustodyValue(Execution memory exec) internal pure returns (HostAmount memory value) {
        (value.host, value.asset, value.amount) = unpackCustody(exec);
    }

    /// @notice Decode and consume one POSITION block from state.
    /// @param exec Execution whose state cursor is advanced.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded asset amount.
    /// @return liability Decoded liability identifier.
    /// @return debt Decoded debt amount.
    /// @return counterparty Decoded settlement counterparty.
    function unpackPosition(
        Execution memory exec
    ) internal pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        uint abs = takeState(exec, Sizes.Position);
        (asset, amount, liability, debt, counterparty) = Blocks.unpackPosition(abs);
    }

    /// @notice Decode and consume one POSITION block from state into its structured value.
    /// @param exec Execution whose state cursor is advanced.
    /// @return value Decoded asset and liability position.
    function unpackPositionValue(Execution memory exec) internal pure returns (Position memory value) {
        (value.asset, value.amount, value.liability, value.debt, value.counterparty) = unpackPosition(exec);
    }

    /// @notice Consume a POSITION from state and enforce LIMITS from input.
    /// @param exec Execution whose state and input cursors are advanced.
    /// @return position Decoded position satisfying the inclusive packed limits.
    function unpackLimitedPosition(Execution memory exec) internal pure returns (Position memory position) {
        uint pos = takeState(exec, Sizes.Position);
        uint lim = take(exec, Sizes.Limits);
        position = Blocks.unpackLimitedPosition(pos, lim);
    }

    /// @notice Decode and consume one BALANCE block from state and associate it with `host`.
    /// @param exec Execution whose state cursor is advanced.
    /// @param host Host associated with the decoded balance.
    /// @return value Host-scoped asset amount.
    function unpackBalanceForHost(Execution memory exec, uint host) internal pure returns (HostAmount memory value) {
        uint abs = takeState(exec, Sizes.Balance);
        value.host = host;
        (value.asset, value.amount) = Blocks.unpackBalance(abs);
    }

    // Remaining fixed-width input decoding

    /// @notice Decode and consume one ACCOUNT_AMOUNT block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackAccountAmount(
        Execution memory exec
    ) internal pure returns (bytes32 account, bytes32 asset, uint amount) {
        uint abs = take(exec, Sizes.B96);
        (account, asset, amount) = Blocks.unpackAccountAmount(abs);
    }

    /// @notice Decode one ACCOUNT_AMOUNT block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded account, asset, and amount.
    function unpackAccountAmountValue(Execution memory exec) internal pure returns (AccountAmount memory value) {
        (value.account, value.asset, value.amount) = unpackAccountAmount(exec);
    }

    /// @notice Decode and consume one ALLOCATION block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackAllocation(Execution memory exec) internal pure returns (uint host, bytes32 asset, uint amount) {
        uint abs = take(exec, Sizes.B96);
        (host, asset, amount) = Blocks.unpackAllocation(abs);
    }

    /// @notice Decode one ALLOCATION block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded host, asset, and amount.
    function unpackAllocationValue(Execution memory exec) internal pure returns (HostAmount memory value) {
        (value.host, value.asset, value.amount) = unpackAllocation(exec);
    }

    /// @notice Decode and consume one ALLOWANCE block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded allowance amount.
    function unpackAllowance(Execution memory exec) internal pure returns (uint host, bytes32 asset, uint amount) {
        uint abs = take(exec, Sizes.B96);
        (host, asset, amount) = Blocks.unpackAllowance(abs);
    }

    /// @notice Decode one ALLOWANCE block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded host, asset, and allowance amount.
    function unpackAllowanceValue(Execution memory exec) internal pure returns (HostAmount memory value) {
        (value.host, value.asset, value.amount) = unpackAllowance(exec);
    }

    /// @notice Decode and consume one HOST_ACCOUNT_ASSET block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return host Decoded host identifier.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    function unpackHostAccountAsset(
        Execution memory exec
    ) internal pure returns (uint host, bytes32 account, bytes32 asset) {
        uint abs = take(exec, Sizes.B96);
        (host, account, asset) = Blocks.unpackHostAccountAsset(abs);
    }

    /// @notice Decode one HOST_ACCOUNT_ASSET block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded host, account, and asset.
    function unpackHostAccountAssetValue(Execution memory exec) internal pure returns (HostAccountAsset memory value) {
        (value.host, value.account, value.asset) = unpackHostAccountAsset(exec);
    }

    /// @notice Decode and consume one TRANSACTION block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return from Decoded debit account.
    /// @return to Decoded credit account.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded transaction amount.
    function unpackTransaction(
        Execution memory exec
    ) internal pure returns (bytes32 from, bytes32 to, bytes32 asset, uint amount) {
        uint abs = take(exec, Sizes.Transaction);
        (from, to, asset, amount) = Blocks.unpackTransaction(abs);
    }

    /// @notice Decode one TRANSACTION block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded transaction.
    function unpackTransactionValue(Execution memory exec) internal pure returns (Tx memory value) {
        (value.from, value.to, value.asset, value.amount) = unpackTransaction(exec);
    }

    // -------------------------------------------------------------------------
    // Dynamic block decoding
    // -------------------------------------------------------------------------

    /// @notice Decode and consume an input block described by `spec`.
    /// @param exec Execution whose input cursor is advanced.
    /// @param spec Expected block specification.
    /// @return data Calldata view of the decoded payload.
    function unpackRaw(Execution memory exec, uint spec) internal pure returns (bytes calldata data) {
        uint abs = uint32(exec.decoders);
        uint end;
        (data, end) = Blocks.unpackRaw(abs, spec);
        seekInput(exec, end);
    }

    /// @notice Decode and consume one BYTES block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return data Decoded byte payload.
    function unpackBytes(Execution memory exec) internal pure returns (bytes calldata data) {
        uint abs = uint32(exec.decoders);
        uint end;
        (data, end) = Blocks.unpackBytes(abs);
        seekInput(exec, end);
    }

    /// @notice Decode and consume one STRING block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return data Decoded string payload.
    function unpackString(Execution memory exec) internal pure returns (string memory data) {
        uint abs = uint32(exec.decoders);
        (bytes calldata value, uint end) = Blocks.unpackString(abs);
        data = string(value);
        seekInput(exec, end);
    }

    /// @notice Decode and consume one STEP block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return cmd Decoded command identifier.
    /// @return value Decoded native value.
    /// @return input Decoded nested input.
    function unpackStep(Execution memory exec) internal pure returns (uint cmd, uint value, bytes calldata input) {
        uint abs = uint32(exec.decoders);
        uint end;
        (cmd, value, input, end) = Blocks.unpackStep(abs);
        seekInput(exec, end);
    }

    /// @notice Decode and consume one CALL block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return target Decoded call target.
    /// @return resources Decoded packed resources.
    /// @return data Decoded call payload.
    function unpackCall(
        Execution memory exec
    ) internal pure returns (uint target, uint resources, bytes calldata data) {
        uint abs = uint32(exec.decoders);
        uint end;
        (target, resources, data, end) = Blocks.unpackCall(abs);
        seekInput(exec, end);
    }

    /// @notice Decode and consume one ANNOTATION block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return entity Decoded entity identifier.
    /// @return data Decoded annotation block stream.
    function unpackAnnotation(Execution memory exec) internal pure returns (uint entity, bytes calldata data) {
        uint abs = uint32(exec.decoders);
        uint end;
        (entity, data, end) = Blocks.unpackAnnotation(abs);
        seekInput(exec, end);
    }

    /// @notice Decode and consume one CONTEXT block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return account Decoded account identifier.
    /// @return state Decoded nested state.
    /// @return input Decoded nested input.
    function unpackContext(
        Execution memory exec
    ) internal pure returns (bytes32 account, bytes calldata state, bytes calldata input) {
        uint abs = uint32(exec.decoders);
        uint end;
        (account, state, input, end) = Blocks.unpackContext(abs);
        seekInput(exec, end);
    }

    /// @notice Decode and consume one RELAY block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return input Decoded nested input.
    /// @return steps Decoded remaining pipeline steps.
    function unpackRelay(Execution memory exec) internal pure returns (bytes calldata input, bytes calldata steps) {
        uint abs = uint32(exec.decoders);
        uint end;
        (input, steps, end) = Blocks.unpackRelay(abs);
        seekInput(exec, end);
    }

    /// @notice Decode and consume one DISPATCH block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return portal Decoded destination portal.
    /// @return resources Decoded packed resources.
    /// @return payload Decoded dispatch payload.
    function unpackDispatch(
        Execution memory exec
    ) internal pure returns (uint portal, uint resources, bytes calldata payload) {
        uint abs = uint32(exec.decoders);
        uint end;
        (portal, resources, payload, end) = Blocks.unpackDispatch(abs);
        seekInput(exec, end);
    }

    /// @notice Decode and consume one LABEL block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return namespace Decoded label namespace.
    /// @return name Decoded label text.
    function unpackLabel(Execution memory exec) internal pure returns (bytes32 namespace, string memory name) {
        uint abs = uint32(exec.decoders);
        uint end;
        (namespace, name, end) = Blocks.unpackLabel(abs);
        seekInput(exec, end);
    }

    /// @notice Decode and consume one SCHEMA block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return spec Decoded block specification.
    /// @return body Decoded schema body.
    /// @return name Decoded schema name.
    function unpackSchema(Execution memory exec) internal pure returns (uint spec, string memory body, bytes32 name) {
        uint abs = uint32(exec.decoders);
        uint end;
        (spec, body, name, end) = Blocks.unpackSchema(abs);
        seekInput(exec, end);
    }

    /// @notice Decode and consume one RECOVER block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return handler Decoded recovery handler.
    /// @return resources Decoded packed resources.
    /// @return key Decoded recovery key.
    /// @return witness Decoded recovery witness.
    function unpackRecover(
        Execution memory exec
    ) internal pure returns (uint handler, uint resources, bytes32 key, bytes calldata witness) {
        uint abs = uint32(exec.decoders);
        uint end;
        (handler, resources, key, witness, end) = Blocks.unpackRecover(abs);
        seekInput(exec, end);
    }

    // -------------------------------------------------------------------------
    // Output writing
    // -------------------------------------------------------------------------

    /// @notice Scale the initial output capacity hint before allocating the backing buffer.
    /// @dev Rounds down. Does not allocate or change decoding; later writes can still grow.
    /// Reverts if output was reserved, the denominator is zero, the product exceeds uint256,
    /// or the resulting capacity exceeds uint32. A zero numerator clears the hint.
    /// @param exec Execution whose output capacity is adjusted.
    /// @param numerator Multiplier applied to the current capacity.
    /// @param denominator Divisor applied after multiplication; must be nonzero.
    function scaleOutput(Execution memory exec, uint numerator, uint denominator) internal pure {
        if (exec.output.length != 0) revert UnexpectedPosition();
        exec.writer = Buffers.scale(exec.writer, numerator, denominator);
    }

    /// @dev Reserve output capacity and advance its writer cursor.
    /// @param exec Execution whose output writer is advanced.
    /// @param amount Logical number of bytes written.
    /// @param touch Number of bytes that must be addressable by the write.
    /// @return i Relative output offset reserved for the write.
    function reserve(Execution memory exec, uint amount, uint touch) internal pure returns (uint i) {
        (exec.writer, exec.output, i) = Buffers.reserve(exec.writer, exec.output, amount, touch);
    }

    /// @dev Reserve an exact number of output bytes.
    /// @param exec Execution whose output writer is advanced.
    /// @param size Number of bytes to reserve and touch.
    /// @return i Relative output offset reserved for the write.
    function reserve(Execution memory exec, uint size) private pure returns (uint i) {
        (exec.writer, exec.output, i) = Buffers.reserve(exec.writer, exec.output, size, size);
    }

    /// @notice Append an empty block to execution output.
    /// @param exec Execution receiving the block.
    /// @param key Block key.
    function outputEmpty(Execution memory exec, bytes4 key) internal pure {
        uint i = reserve(exec, Sizes.Header);
        Blocks.writeEmpty(exec.output, i, key);
    }

    /// @notice Append an ACCOUNT block to execution output.
    /// @param exec Execution receiving the block.
    /// @param account Account identifier to encode.
    function outputAccount(Execution memory exec, bytes32 account) internal pure {
        uint i = reserve(exec, Sizes.B32);
        Blocks.writeAccount(exec.output, i, account);
    }

    /// @notice Append an ASSET block to execution output.
    /// @param exec Execution receiving the block.
    /// @param asset Asset identifier to encode.
    function outputAsset(Execution memory exec, bytes32 asset) internal pure {
        uint i = reserve(exec, Sizes.B32);
        Blocks.writeAsset(exec.output, i, asset);
    }

    /// @notice Append a NODE block to execution output.
    /// @param exec Execution receiving the block.
    /// @param node Node identifier to encode.
    function outputNode(Execution memory exec, uint node) internal pure {
        uint i = reserve(exec, Sizes.B32);
        Blocks.writeNode(exec.output, i, node);
    }

    /// @notice Append a STATUS block to execution output.
    /// @param exec Execution receiving the block.
    /// @param code Status code to encode.
    function outputStatus(Execution memory exec, uint code) internal pure {
        uint i = reserve(exec, Sizes.B32);
        Blocks.writeStatus(exec.output, i, code);
    }

    /// @notice Append an AMOUNT block to execution output.
    /// @param exec Execution receiving the block.
    /// @param asset Asset identifier to encode.
    /// @param amount Asset amount to encode.
    function outputAmount(Execution memory exec, bytes32 asset, uint amount) internal pure {
        uint i = reserve(exec, Sizes.B64);
        Blocks.writeAmount(exec.output, i, asset, amount);
    }

    /// @notice Append a structured AMOUNT value to execution output.
    /// @param exec Execution receiving the block.
    /// @param value Structured asset amount to encode.
    function outputAmount(Execution memory exec, AssetAmount memory value) internal pure {
        outputAmount(exec, value.asset, value.amount);
    }

    /// @notice Append a BALANCE block to execution output.
    /// @param exec Execution receiving the block.
    /// @param asset Asset identifier to encode.
    /// @param amount Balance amount to encode.
    function outputBalance(Execution memory exec, bytes32 asset, uint amount) internal pure {
        uint i = reserve(exec, Sizes.B64);
        Blocks.writeBalance(exec.output, i, asset, amount);
    }

    /// @notice Append a structured BALANCE value to execution output.
    /// @param exec Execution receiving the block.
    /// @param value Structured asset balance to encode.
    function outputBalance(Execution memory exec, AssetAmount memory value) internal pure {
        outputBalance(exec, value.asset, value.amount);
    }

    /// @notice Append a LIMITS block with minimum amount and maximum debt.
    /// @param limits Packed minimum asset amount (high 128 bits) and maximum debt (low 128 bits).
    function outputLimits(Execution memory exec, uint limits) internal pure {
        uint i = reserve(exec, Sizes.Limits);
        Blocks.writeLimits(exec.output, i, limits);
    }

    /// @notice Append a QUOTE with minimum amount and maximum debt.
    function outputQuote(
        Execution memory exec,
        bytes32 asset,
        bytes32 liability,
        bytes32 counterparty,
        uint limits
    ) internal pure {
        uint i = reserve(exec, Sizes.Quote);
        Blocks.writeQuote(exec.output, i, asset, liability, counterparty, limits);
    }

    /// @notice Append a structured QUOTE.
    function outputQuote(Execution memory exec, Quote memory quote) internal pure {
        outputQuote(exec, quote.asset, quote.liability, quote.counterparty, quote.limits);
    }

    /// @notice Append a POSITION block to execution output.
    function outputPosition(
        Execution memory exec,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        bytes32 counterparty
    ) internal pure {
        uint i = reserve(exec, Sizes.Position);
        Blocks.writePosition(exec.output, i, asset, amount, liability, debt, counterparty);
    }

    /// @notice Append a structured POSITION value to execution output.
    function outputPosition(Execution memory exec, Position memory value) internal pure {
        outputPosition(exec, value.asset, value.amount, value.liability, value.debt, value.counterparty);
    }

    /// @notice Append an ACCOUNT_ASSET block to execution output.
    /// @param exec Execution receiving the block.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    function outputAccountAsset(Execution memory exec, bytes32 account, bytes32 asset) internal pure {
        uint i = reserve(exec, Sizes.B64);
        Blocks.writeAccountAsset(exec.output, i, account, asset);
    }

    /// @notice Append an ASSET_LIABILITY block to execution output.
    /// @param exec Execution receiving the block.
    /// @param asset Asset identifier to encode.
    /// @param liability Liability identifier to encode.
    function outputAssetLiability(Execution memory exec, bytes32 asset, bytes32 liability) internal pure {
        uint i = reserve(exec, Sizes.B64);
        Blocks.writeAssetLiability(exec.output, i, asset, liability);
    }

    /// @notice Append a structured ASSET_LIABILITY value to execution output.
    function outputAssetLiability(Execution memory exec, AssetLiability memory value) internal pure {
        outputAssetLiability(exec, value.asset, value.liability);
    }

    /// @notice Append a HOST_ASSET block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    function outputHostAsset(Execution memory exec, uint host, bytes32 asset) internal pure {
        uint i = reserve(exec, Sizes.HostAsset);
        Blocks.writeHostAsset(exec.output, i, host, asset);
    }

    /// @notice Append an ALLOCATION block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Allocation amount to encode.
    function outputAllocation(Execution memory exec, uint host, bytes32 asset, uint amount) internal pure {
        uint i = reserve(exec, Sizes.B96);
        Blocks.writeAllocation(exec.output, i, host, asset, amount);
    }

    /// @notice Append an ALLOWANCE block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Allowance amount to encode.
    function outputAllowance(Execution memory exec, uint host, bytes32 asset, uint amount) internal pure {
        uint i = reserve(exec, Sizes.B96);
        Blocks.writeAllowance(exec.output, i, host, asset, amount);
    }

    /// @notice Append a CUSTODY block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Custody amount to encode.
    function outputCustody(Execution memory exec, uint host, bytes32 asset, uint amount) internal pure {
        uint i = reserve(exec, Sizes.Custody);
        Blocks.writeCustody(exec.output, i, host, asset, amount);
    }

    /// @notice Append a CUSTODY block for `host` and a structured amount.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param value Structured asset amount to encode.
    function outputCustody(Execution memory exec, uint host, AssetAmount memory value) internal pure {
        outputCustody(exec, host, value.asset, value.amount);
    }

    /// @notice Append a structured CUSTODY value to execution output.
    /// @param exec Execution receiving the block.
    /// @param value Structured host asset amount to encode.
    function outputCustody(Execution memory exec, HostAmount memory value) internal pure {
        outputCustody(exec, value.host, value.asset, value.amount);
    }

    /// @notice Append an ACCOUNT_AMOUNT block to execution output.
    /// @param exec Execution receiving the block.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Account amount to encode.
    function outputAccountAmount(Execution memory exec, bytes32 account, bytes32 asset, uint amount) internal pure {
        uint i = reserve(exec, Sizes.B96);
        Blocks.writeAccountAmount(exec.output, i, account, asset, amount);
    }

    /// @notice Append a structured ACCOUNT_AMOUNT value to execution output.
    /// @param exec Execution receiving the block.
    /// @param value Structured account asset amount to encode.
    function outputAccountAmount(Execution memory exec, AccountAmount memory value) internal pure {
        outputAccountAmount(exec, value.account, value.asset, value.amount);
    }

    /// @notice Append a HOST_AMOUNT block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Host amount to encode.
    function outputHostAmount(Execution memory exec, uint host, bytes32 asset, uint amount) internal pure {
        uint i = reserve(exec, Sizes.B96);
        Blocks.writeHostAmount(exec.output, i, host, asset, amount);
    }

    /// @notice Append a HOST_ACCOUNT_ASSET block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    function outputHostAccountAsset(Execution memory exec, uint host, bytes32 account, bytes32 asset) internal pure {
        uint i = reserve(exec, Sizes.B96);
        Blocks.writeHostAccountAsset(exec.output, i, host, account, asset);
    }

    /// @notice Append a TRANSACTION block to regular execution output.
    /// @param exec Execution receiving the block.
    /// @param from Debit account identifier.
    /// @param to Credit account identifier.
    /// @param asset Asset identifier to encode.
    /// @param amount Transaction amount to encode.
    function outputTransaction(
        Execution memory exec,
        bytes32 from,
        bytes32 to,
        bytes32 asset,
        uint amount
    ) internal pure {
        uint i = reserve(exec, Sizes.B128);
        Blocks.writeTransaction(exec.output, i, from, to, asset, amount);
    }

    /// @notice Append a structured TRANSACTION value to regular execution output.
    /// @param exec Execution receiving the block.
    /// @param value Structured transaction to encode.
    function outputTransaction(Execution memory exec, Tx memory value) internal pure {
        outputTransaction(exec, value.from, value.to, value.asset, value.amount);
    }

    /// @notice Append a HOST_ACCOUNT_AMOUNT block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Host account amount to encode.
    function outputHostAccountAmount(
        Execution memory exec,
        uint host,
        bytes32 account,
        bytes32 asset,
        uint amount
    ) internal pure {
        uint i = reserve(exec, Sizes.B128);
        Blocks.writeHostAccountAmount(exec.output, i, host, account, asset, amount);
    }

    /// @notice Append a LIST block to execution output.
    /// @param exec Execution receiving the block.
    /// @param value Encoded list payload.
    function outputList(Execution memory exec, bytes memory value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(exec, size);
        Blocks.writeList(exec.output, i, value);
    }

    /// @notice Append a BYTES block to execution output.
    /// @param exec Execution receiving the block.
    /// @param value Byte payload to encode.
    function outputBytes(Execution memory exec, bytes memory value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(exec, size);
        Blocks.writeBytes(exec.output, i, value);
    }

    /// @notice Append a STRING block to execution output.
    /// @param exec Execution receiving the block.
    /// @param value String payload to encode.
    function outputString(Execution memory exec, string memory value) internal pure {
        uint size = Sizes.Header + bytes(value).length;
        uint i = reserve(exec, size);
        Blocks.writeString(exec.output, i, value);
    }

    /// @notice Append a STEP block to execution output.
    /// @param exec Execution receiving the block.
    /// @param cmd Command identifier to encode.
    /// @param value Native value to encode.
    /// @param input Command input to encode.
    function outputStep(Execution memory exec, uint cmd, uint value, bytes memory input) internal pure {
        uint size = Sizes.Step + input.length;
        uint i = reserve(exec, size);
        Blocks.writeCompositeSized(exec.output, i, bytes4(uint32(Specs.Step >> 224)), cmd, value, input, size);
    }

    /// @notice Append a CALL block to execution output.
    /// @param exec Execution receiving the block.
    /// @param target Call target to encode.
    /// @param resources Packed resources to encode.
    /// @param payload Call payload to encode.
    function outputCall(Execution memory exec, uint target, uint resources, bytes memory payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        Blocks.writeCompositeSized(exec.output, i, bytes4(uint32(Specs.Call >> 224)), target, resources, payload, size);
    }

    /// @notice Append a RELAY block to execution output.
    /// @param exec Execution receiving the block.
    /// @param input Relay input to encode.
    /// @param steps Remaining pipeline steps to encode.
    function outputRelay(Execution memory exec, bytes memory input, bytes memory steps) internal pure {
        uint size = 3 * Sizes.Header + input.length + steps.length;
        uint i = reserve(exec, size);
        Blocks.writeRelaySized(exec.output, i, input, steps, size);
    }

    /// @notice Append a DISPATCH block to execution output.
    /// @param exec Execution receiving the block.
    /// @param portal Destination portal to encode.
    /// @param resources Packed resources to encode.
    /// @param payload Dispatch payload to encode.
    function outputDispatch(Execution memory exec, uint portal, uint resources, bytes memory payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        Blocks.writeCompositeSized(exec.output, i, bytes4(uint32(Specs.Dispatch >> 224)), portal, resources, payload, size);
    }

    /// @notice Append a CONTEXT block to execution output.
    /// @param exec Execution receiving the block.
    /// @param account Account identifier to encode.
    /// @param state State payload to encode.
    /// @param input Input payload to encode.
    function outputContext(
        Execution memory exec,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure {
        uint size = Sizes.B32 + 2 * Sizes.Header + state.length + input.length;
        uint i = reserve(exec, size);
        Blocks.writeContextSized(exec.output, i, account, state, input, size);
    }

    /// @notice Append a RECOVER block to execution output.
    /// @param exec Execution receiving the block.
    /// @param handler Recovery handler to encode.
    /// @param resources Packed resources to encode.
    /// @param recoverykey Recovery key to encode.
    /// @param witness Recovery witness to encode.
    function outputRecover(
        Execution memory exec,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes memory witness
    ) internal pure {
        uint size = Sizes.B96 + Sizes.Header + witness.length;
        uint i = reserve(exec, size);
        Blocks.writeRecoverSized(exec.output, i, handler, resources, recoverykey, witness, size);
    }

    /// @notice Append a LABEL block to execution output.
    /// @param exec Execution receiving the block.
    /// @param namespace Label namespace to encode.
    /// @param name Label text to encode.
    function outputLabel(Execution memory exec, bytes32 namespace, string memory name) internal pure {
        uint size = Sizes.B32 + Sizes.Header + bytes(name).length;
        uint i = reserve(exec, size);
        Blocks.writeLabelSized(exec.output, i, namespace, name, size);
    }

    /// @notice Append a SCHEMA block to execution output.
    /// @param exec Execution receiving the block.
    /// @param spec Block specification to encode.
    /// @param body Schema body to encode.
    /// @param name Schema name to encode.
    function outputSchema(Execution memory exec, uint spec, string memory body, bytes32 name) internal pure {
        uint size = Sizes.B64 + Sizes.Header + bytes(body).length;
        uint i = reserve(exec, size);
        Blocks.writeSchemaSized(exec.output, i, spec, body, name, size);
    }

    // -------------------------------------------------------------------------
    // Calldata output copy helpers
    // -------------------------------------------------------------------------

    /// @notice Append a custom block to execution output by copying its payload from calldata.
    function outputCopyBlock(Execution memory exec, uint spec, bytes calldata data) internal pure {
        Specs.validate(spec, data.length);
        uint size = Sizes.Header + data.length;
        uint i = reserve(exec, size);
        Blocks.copySized(exec.output, i, Specs.key(spec), data, data.length);
    }

    /// @notice Append a LIST block to execution output by copying its payload from calldata.
    function outputCopyList(Execution memory exec, bytes calldata value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(exec, size);
        Blocks.copySized(exec.output, i, bytes4(uint32(Specs.List >> 224)), value, value.length);
    }

    /// @notice Append a BYTES block to execution output by copying its payload from calldata.
    function outputCopyBytes(Execution memory exec, bytes calldata value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(exec, size);
        Blocks.copySized(exec.output, i, bytes4(uint32(Specs.Bytes >> 224)), value, value.length);
    }

    /// @notice Append a STRING block to execution output by copying its payload from calldata.
    function outputCopyString(Execution memory exec, string calldata value) internal pure {
        uint size = Sizes.Header + bytes(value).length;
        uint i = reserve(exec, size);
        Blocks.copySized(exec.output, i, bytes4(uint32(Specs.String >> 224)), bytes(value), bytes(value).length);
    }

    /// @notice Append a STEP block to execution output by copying its nested input from calldata.
    function outputCopyStep(Execution memory exec, uint cmd, uint value, bytes calldata input) internal pure {
        uint size = Sizes.Step + input.length;
        uint i = reserve(exec, size);
        Blocks.copyCompositeSized(exec.output, i, bytes4(uint32(Specs.Step >> 224)), cmd, value, input, size);
    }

    /// @notice Append a CALL block to execution output by copying its nested payload from calldata.
    function outputCopyCall(Execution memory exec, uint target, uint resources, bytes calldata payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        Blocks.copyCompositeSized(exec.output, i, bytes4(uint32(Specs.Call >> 224)), target, resources, payload, size);
    }

    /// @notice Append a RELAY block to execution output by copying its nested streams from calldata.
    function outputCopyRelay(Execution memory exec, bytes calldata input, bytes calldata steps) internal pure {
        uint size = 3 * Sizes.Header + input.length + steps.length;
        uint i = reserve(exec, size);
        Blocks.copyRelaySized(exec.output, i, input, steps, size);
    }

    /// @notice Append a DISPATCH block to execution output by copying its nested payload from calldata.
    function outputCopyDispatch(
        Execution memory exec,
        uint portal,
        uint resources,
        bytes calldata payload
    ) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        Blocks.copyCompositeSized(exec.output, i, bytes4(uint32(Specs.Dispatch >> 224)), portal, resources, payload, size);
    }

    /// @notice Append a CONTEXT block to execution output by copying its nested streams from calldata.
    function outputCopyContext(
        Execution memory exec,
        bytes32 account,
        bytes calldata state,
        bytes calldata input
    ) internal pure {
        uint size = Sizes.B32 + 2 * Sizes.Header + state.length + input.length;
        uint i = reserve(exec, size);
        Blocks.copyContextSized(exec.output, i, account, state, input, size);
    }

    /// @notice Append a RECOVER block to execution output by copying its nested witness from calldata.
    function outputCopyRecover(
        Execution memory exec,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes calldata witness
    ) internal pure {
        uint size = Sizes.B96 + Sizes.Header + witness.length;
        uint i = reserve(exec, size);
        Blocks.copyRecoverSized(exec.output, i, handler, resources, recoverykey, witness, size);
    }

    // -------------------------------------------------------------------------
    // Value
    // -------------------------------------------------------------------------

    /// @notice Remove and return the remaining execution value budget.
    /// @param exec Execution whose budget is drained.
    /// @return budget Native value removed from the execution.
    function drainBudget(Execution memory exec) internal pure returns (uint budget) {
        budget = exec.budget;
        exec.budget = 0;
    }

    /// @notice Transfer the remaining value budget out of an execution.
    /// @dev Clears `exec.budget` so the returned budget becomes its sole owner.
    /// @param exec Execution whose budget is detached.
    /// @return budget Detached budget containing the remaining value.
    function takeBudget(Execution memory exec) internal pure returns (Budget memory budget) {
        budget.remaining = drainBudget(exec);
    }

    /// @notice Deduct an exact native value from the execution budget.
    /// @param exec Mutable execution whose budget is charged.
    /// @param value Native value to consume in wei.
    /// @return The consumed native value.
    function useValue(Execution memory exec, uint value) internal pure returns (uint) {
        if (value > exec.budget) revert InsufficientValue();
        unchecked { exec.budget -= value; }
        return value;
    }

    /// @notice Add trusted native value to the execution budget.
    /// @dev This updates accounting only. The caller must ensure the added value
    /// is backed by native value held by the host or otherwise made available.
    /// @param exec Mutable execution whose budget is credited.
    /// @param value Native value to add in wei.
    function addValue(Execution memory exec, uint value) internal pure {
        exec.budget += value;
    }

    /// @notice Deduct the EVM value lane of `resources` from the execution budget.
    /// @dev `resources` is not a native value. This helper explicitly extracts
    /// its low 128-bit EVM value lane and widens that lane to a plain `uint`.
    /// @param exec Mutable execution whose budget is charged.
    /// @param resources Packed resources whose value lane should be spent.
    /// @return value Native value to forward in wei.
    function useResourceValue(Execution memory exec, uint resources) internal pure returns (uint value) {
        value = uint128(resources);
        useValue(exec, value);
    }

    // -------------------------------------------------------------------------
    // Calls
    // -------------------------------------------------------------------------

    /// @notice Call a port with memory input and update the execution budget.
    /// @dev Debits value before calling and adds the returned trusted credit.
    /// The caller must authorize the selector/target and ensure credit is backed;
    /// this helper does not transfer ETH back.
    /// @param exec Mutable execution whose budget funds the call and receives credit.
    /// @param selector Selector of a `bytes -> (bytes, uint)` port.
    /// @param target Target contract address.
    /// @param value Native value to forward in wei.
    /// @param input Raw contents of the port's `bytes` argument.
    /// @param expectEmpty Whether the decoded output must be empty.
    /// @return out Decoded output bytes returned by the target.
    function rawCall(
        Execution memory exec,
        bytes4 selector,
        address target,
        uint value,
        bytes memory input,
        bool expectEmpty
    ) internal returns (bytes memory out) {
        if (value > exec.budget) revert InsufficientValue();
        unchecked { exec.budget -= value; }

        uint credit;
        (out, credit) = Calls.raw(selector, target, value, input, expectEmpty);
        exec.budget += credit;
    }

    /// @notice Call a port with calldata input and update the execution budget.
    /// @dev Copies input directly from calldata. Debits value before calling and
    /// adds the returned trusted credit. The caller must authorize the selector/target
    /// and ensure credit is backed; this helper does not transfer ETH back.
    /// @param exec Mutable execution whose budget funds the call and receives credit.
    /// @param selector Selector of a `bytes -> (bytes, uint)` port.
    /// @param target Target contract address.
    /// @param value Native value to forward in wei.
    /// @param input Raw contents of the port's `bytes` argument.
    /// @param expectEmpty Whether the decoded output must be empty.
    /// @return out Decoded output bytes returned by the target.
    function rawCallCopy(
        Execution memory exec,
        bytes4 selector,
        address target,
        uint value,
        bytes calldata input,
        bool expectEmpty
    ) internal returns (bytes memory out) {
        if (value > exec.budget) revert InsufficientValue();
        unchecked { exec.budget -= value; }

        uint credit;
        (out, credit) = Calls.rawCopy(selector, target, value, input, expectEmpty);
        exec.budget += credit;
    }

    // -------------------------------------------------------------------------
    // Finalization
    // -------------------------------------------------------------------------

    /// @notice Finalize and return regular execution output.
    /// @param exec Execution whose output is finalized.
    /// @return out Trimmed output bytes.
    function finish(Execution memory exec) internal pure returns (bytes memory out) {
        if (more(exec)) revert UnconsumedData();
        if (exec.output.length == 0) return new bytes(0);

        out = Buffers.finish(exec.writer, exec.output);
    }

    /// @notice Close an execution and return its output and remaining budget.
    /// @param exec Execution whose sources, writer, and budget are finalized.
    /// @return output Final encoded output block stream.
    /// @return credit Remaining native value to credit to the caller's budget.
    function close(Execution memory exec) internal pure returns (bytes memory output, uint credit) {
        return close(exec, 0);
    }

    /// @notice Close an execution and combine its remaining budget with additional command credit.
    /// @param exec Execution whose sources, writer, and budget are finalized.
    /// @param extraCredit Additional trusted credit produced by the command.
    /// @return output Final encoded output block stream.
    /// @return credit Remaining execution budget plus `extraCredit`.
    function close(Execution memory exec, uint extraCredit) internal pure returns (bytes memory output, uint credit) {
        output = finish(exec);
        credit = exec.budget + extraCredit;
        exec.budget = 0;
    }
}
