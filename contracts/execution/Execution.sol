// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Headers} from "../codec/Headers.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Specs, Sizes} from "../codec/Specs.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Math} from "../utils/Math.sol";
import {Budget} from "../core/Budget.sol";
import {Calls} from "../core/Calls.sol";
import {
    InsufficientValue,
    OutOfBounds,
    UnconsumedData
} from "../utils/Errors.sol";
import {
    AssetAmount,
    AssetLiability,
    AccountAsset,
    HostAsset,
    AccountBalance,
    AccountAmount,
    HostAmount,
    HostAccountAsset,
    BalanceConstraints,
    PositionConstraints,
    Quote,
    Position,
    Booking
} from "../core/Types.sol";

/// @notice Mutable state shared across one endpoint execution.
/// @dev `input` and `state` are independent packed calldata cursors: current
/// position in bits 0-31 and exclusive end in bits 32-63. Higher bits are unused.
struct Execution {
    /// @dev Trusted active account; context decoding checks structure, not account format.
    /// Untrusted account input must be validated at entry before internal execution.
    bytes32 account;
    /// @dev Remaining native-value budget, in wei.
    uint budget;
    /// @dev Packed calldata cursor over unconsumed input blocks.
    uint input;
    /// @dev Packed calldata cursor over unconsumed state blocks.
    uint state;
    /// @dev Packed output writer: written offset in bits 0-31, capacity in bits 32-63.
    uint output;
    /// @dev Growable memory backing the output cursor; finish exposes only written bytes.
    bytes buffer;
}

/// @title Executions
/// @notice Opening, decoding, output, and value helpers for executions.
/// @dev Cursor output helpers copy complete validated blocks; cursor Wrap helpers
/// add headers around payloads. Memory output overloads retain their payload API.
library Executions {
    using Encoder for uint;
    using Blocks for uint;

    // -------------------------------------------------------------------------
    // Description and opening
    // -------------------------------------------------------------------------

    /// @dev Internal execution flags; distinct from public endpoint Flags.
    uint internal constant StateSource = 1 << 0;
    /// @dev Internal descriptor flag allowing byte-for-byte output capacity estimation.
    uint internal constant ByteCapacity = 1 << 5;

    /// @notice Precompute allocation hints for execution.
    /// @dev Layout: [source key:4][source block size:4][output block size:4]
    /// [reserved:19][flags:1]. Sizes include headers and require 25 bits at maximum hint.
    /// Declared state takes precedence over input, even when supplied state is empty.
    /// Zero output size disables preallocation; no source reserves one output block.
    /// State/input/output may carry low 32-bit lane keys, ignored by the descriptor.
    /// The low byte contains internal source and capacity selections.
    /// @param state State block specification or named lane.
    /// @param input Input block specification or named lane.
    /// @param output Output block specification or named lane.
    /// @return descriptor Packed source and output allocation hints with internal execution flags.
    function describe(uint state, uint input, uint output) internal pure returns (uint descriptor) {
        if (uint104((state | input | output) >> 32) != 0) revert Specs.InvalidSpec();
        bool stateSource = Specs.key(state) != bytes4(0);
        uint source = stateSource ? state : input;
        uint sourceSize = Specs.blockSize(source);
        uint outputSize = Specs.blockSize(output);
        descriptor =
            (uint(uint32(Specs.key(source))) << 224) |
            (sourceSize << 192) |
            (outputSize << 160) |
            (stateSource ? StateSource : 0) |
            (sourceSize != 0 && sourceSize == outputSize
                && uint32(source >> 160) != 0 && uint32(output >> 160) != 0
                && uint32(source >> 192) == uint32(source >> 160)
                && uint32(output >> 192) == uint32(output >> 160) ? ByteCapacity : 0);
    }

    /// @dev Capacity is only a hint; decoding validates the stream and buffers can grow.
    /// @param input Bounded calldata cursor over the input stream.
    /// @param state Bounded calldata cursor over the state stream.
    /// @param descriptor Packed execution allocation hints.
    /// @return capacity Suggested initial output capacity, in bytes.
    function outputCapacity(uint input, uint state, uint descriptor) private pure returns (uint capacity) {
        if (uint32(descriptor >> 160) == 0) return 0;
        if (descriptor & ByteCapacity != 0) return Encoder.length(descriptor & StateSource != 0 ? state : input);
        uint count = 1;
        bytes4 key = bytes4(uint32(descriptor >> 224));
        if (key != bytes4(0)) {
            uint source = (descriptor & StateSource) != 0 ? state : input;
            uint abs = uint32(source);
            uint end = uint32(source >> 32);
            uint blockSize = uint32(descriptor >> 192);
            if (blockSize != 0 && (end - abs) % blockSize == 0) {
                count = (end - abs) / blockSize;
            } else {
                count = source.runCount(key);
            }
        }
        // Source positions and block sizes are uint32. Both counting paths
        // produce at most uint32.max blocks, so the product fits uint64.
        // Encoder.init enforces the uint32 capacity limit.
        unchecked {
            capacity = count * uint32(descriptor >> 160);
        }
    }

    /// @notice Open an execution containing only the current call-value budget.
    /// @dev Input/state cursors remain empty; initializes a growable output writer.
    /// @return exec Budget-only execution initialized with `msg.value`.
    function open() internal view returns (Execution memory exec) {
        exec.budget = msg.value;
        (exec.buffer, exec.output) = Encoder.init(0);
    }

    /// @notice Initialize an input-only execution and its native-value budget.
    /// @dev Requires a fresh execution; account may be supplied before opening.
    /// @param exec Execution to initialize.
    /// @param descriptor Packed endpoint descriptor.
    /// @param budget Initial native-value budget.
    /// @param input Descriptor-backed input source.
    function openInput(Execution memory exec, uint descriptor, uint budget, bytes calldata input) internal pure {
        exec.input = Cursors.wrap(input);
        exec.budget = budget;
        (exec.buffer, exec.output) = Encoder.init(outputCapacity(exec.input, 0, descriptor));
    }

    /// @notice Open an execution with its output-capacity hint scaled before allocation.
    /// @dev Requires an empty exec. The ratio changes only allocation, not source validation
    /// or output limits; the buffer can grow. Division rounds down. A zero denominator
    /// reverts ZeroAmount; product overflow or a final capacity above uint32.max reverts ValueOverflow.
    /// @param exec Execution to initialize.
    /// @param descriptor Packed endpoint descriptor used to calculate the base capacity once.
    /// @param budget Initial native-value budget.
    /// @param input Calldata source, decoded identically to the default overload.
    /// @param numerator Capacity multiplier; zero starts with zero logical capacity.
    /// @param denominator Nonzero capacity divisor.
    function openInput(
        Execution memory exec,
        uint descriptor,
        uint budget,
        bytes calldata input,
        uint numerator,
        uint denominator
    ) internal pure {
        exec.input = Cursors.wrap(input);
        exec.budget = budget;
        uint capacity = outputCapacity(exec.input, 0, descriptor);
        (exec.buffer, exec.output) = Encoder.init(Math.scale(capacity, numerator, denominator));
    }

    /// @notice Decode exactly one context and initialize a complete command execution.
    /// @dev `exec` must be newly allocated or otherwise empty. Initializes both
    /// source cursors independently. Rejects trailing context bytes.
    /// @param exec Execution to initialize.
    /// @param descriptor Packed command descriptor.
    /// @param budget Initial native-value budget.
    /// @param context Exactly one CONTEXT block carrying account, state, and input.
    function openContext(Execution memory exec, uint descriptor, uint budget, bytes calldata context) internal pure {
        (exec.account, exec.state, exec.input) = Blocks.unpackContextExact(Cursors.wrap(context));
        exec.budget = budget;
        (exec.buffer, exec.output) = Encoder.init(outputCapacity(exec.input, exec.state, descriptor));
    }

    /// @notice Open an execution with its output-capacity hint scaled before allocation.
    /// @dev Requires an empty exec. The ratio changes only allocation, not source validation
    /// or output limits; the buffer can grow. Division rounds down. A zero denominator
    /// reverts ZeroAmount; product overflow or a final capacity above uint32.max reverts ValueOverflow.
    /// @param exec Execution to initialize.
    /// @param descriptor Packed endpoint descriptor used to calculate the base capacity once.
    /// @param budget Initial native-value budget.
    /// @param context Calldata source, decoded identically to the default overload.
    /// @param numerator Capacity multiplier; zero starts with zero logical capacity.
    /// @param denominator Nonzero capacity divisor.
    function openContext(
        Execution memory exec,
        uint descriptor,
        uint budget,
        bytes calldata context,
        uint numerator,
        uint denominator
    ) internal pure {
        (exec.account, exec.state, exec.input) = Blocks.unpackContextExact(Cursors.wrap(context));
        exec.budget = budget;
        uint capacity = outputCapacity(exec.input, exec.state, descriptor);
        (exec.buffer, exec.output) = Encoder.init(Math.scale(capacity, numerator, denominator));
    }

    // -------------------------------------------------------------------------
    // Traversal
    // -------------------------------------------------------------------------

    // Source inspection

    /// @notice Return whether either execution source has blocks remaining.
    /// @param exec Execution to inspect.
    /// @return Whether either decoder source has unread bytes.
    function more(Execution memory exec) internal pure returns (bool) {
        uint input = exec.input;
        uint state = exec.state;
        return Cursors.more(input) || Cursors.more(state);
    }

    // Whole-source selection: validate the stream, then consume its execution lane.
    // Source cursors must come from opening helpers or another validated calldata range.

    /// @dev Mark a range already validated by an exact selector fully consumed.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function exhaustInput(Execution memory exec) private pure {
        exec.input = Cursors.exhaust(exec.input);
    }

    // Block selection: enter, take, unpack. Selection consumes the parent in input.

    /// @notice Consume one block, validate a fixed prefix, and select its remaining payload.
    /// @dev Blocks validates the block and prefix once. Input advances past the parent.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param spec Packed block specification or named lane.
    /// @param amount Number of source bytes to consume.
    /// @return abs Original payload address; amount bytes are safe to read.
    /// @return payloadCur Clean cursor over the payload after the prefix.
    function enter(Execution memory exec, uint spec, uint amount) internal pure returns (uint abs, uint payloadCur) {
        (abs, payloadCur, exec.input) = exec.input.enter(spec, amount);
    }

    /// @notice Consume one block, validate a fixed prefix, and select its remaining payload.
    /// @dev Blocks validates the block and prefix once. Input advances past the parent.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param key Block key.
    /// @param amount Number of source bytes to consume.
    /// @return abs Original payload address; amount bytes are safe to read.
    /// @return payloadCur Clean cursor over the payload after the prefix.
    function enter(Execution memory exec, bytes4 key, uint amount) internal pure returns (uint abs, uint payloadCur) {
        (abs, payloadCur, exec.input) = exec.input.enter(key, amount);
    }

    /// @notice Consume one block, validate a fixed prefix, and select its remaining payload.
    /// @dev Blocks validates the block and prefix once. Input advances past the parent.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param header Right-aligned 8-byte block header containing the key and exact payload size.
    /// @param amount Number of source bytes to consume.
    /// @return abs Original payload address; amount bytes are safe to read.
    /// @return payloadCur Clean cursor over the payload after the prefix.
    function enterFixed(
        Execution memory exec,
        uint header,
        uint amount
    ) internal pure returns (uint abs, uint payloadCur) {
        (abs, payloadCur, exec.input) = exec.input.enterFixed(header, amount);
    }

    /// @notice Consume the entire input as one matching block and select its fixed prefix and tail.
    /// @dev Reuses Blocks exact validation; no separate source-bound check is needed.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param spec Packed block specification or named lane.
    /// @param amount Number of source bytes to consume.
    /// @return abs Absolute calldata position of the selected bytes.
    /// @return payloadCur Clean calldata cursor over the payload.
    function enterExact(
        Execution memory exec,
        uint spec,
        uint amount
    ) internal pure returns (uint abs, uint payloadCur) {
        (abs, payloadCur) = exec.input.enterExact(spec, amount);
        exhaustInput(exec);
    }

    /// @notice Consume one input block and return its complete encoding as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return blockCur Clean calldata cursor over the complete block, including its header.
    function take(Execution memory exec) internal pure returns (uint blockCur) {
        (blockCur, exec.input) = exec.input.take();
    }

    /// @notice Consume one input block and return its complete encoding as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param spec Packed block specification or named lane.
    /// @return blockCur Clean calldata cursor over the complete block, including its header.
    function take(Execution memory exec, uint spec) internal pure returns (uint blockCur) {
        (blockCur, exec.input) = exec.input.take(spec);
    }

    /// @notice Consume one input block and return its complete encoding as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param key Block key.
    /// @return blockCur Clean calldata cursor over the complete block, including its header.
    function take(Execution memory exec, bytes4 key) internal pure returns (uint blockCur) {
        (blockCur, exec.input) = exec.input.take(key);
    }

    /// @notice Consume one input block and return its complete encoding as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param header Right-aligned 8-byte block header containing the key and exact payload size.
    /// @return blockCur Clean calldata cursor over the complete block, including its header.
    function takeFixed(Execution memory exec, uint header) internal pure returns (uint blockCur) {
        (blockCur, exec.input) = exec.input.takeFixed(header);
    }

    /// @notice Consume the entire input as one matching block and return its complete encoding as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param spec Packed block specification or named lane.
    /// @return blockCur Clean calldata cursor over the complete block, including its header.
    function takeExact(Execution memory exec, uint spec) internal pure returns (uint blockCur) {
        blockCur = exec.input.takeExact(spec);
        exhaustInput(exec);
    }

    /// @notice Consume the entire input as one exact-header block and return its complete encoding.
    /// @dev Delegates validation to Blocks; returns a clean child and preserves input metadata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param header Right-aligned 8-byte block header containing the key and exact payload size.
    /// @return blockCur Clean calldata cursor over the complete block, including its header.
    function takeFixedExact(Execution memory exec, uint header) internal pure returns (uint blockCur) {
        blockCur = exec.input.takeFixedExact(header);
        exhaustInput(exec);
    }

    /// @notice Validate and consume all remaining input blocks with key.
    /// @dev Empty streams pass. Validates the requested key regardless of descriptor
    /// declarations; close still rejects any source bytes left unread.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param key Block key.
    /// @return inputCur Clean calldata cursor over the INPUT payload.
    function takeInput(Execution memory exec, bytes4 key) internal pure returns (uint inputCur) {
        inputCur = exec.input;
        inputCur.expectRun(key);
        exec.input = Cursors.exhaust(inputCur);
    }

    /// @notice Validate and consume all remaining input blocks with an exact header.
    /// @dev Shares takeInput's empty-stream behavior; descriptor declarations do not affect validation.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param header Right-aligned 8-byte block header containing the key and exact payload size.
    /// @return inputCur Clean calldata cursor over the INPUT payload.
    function takeInputFixed(Execution memory exec, uint header) internal pure returns (uint inputCur) {
        inputCur = exec.input;
        inputCur.expectRunFixed(header);
        exec.input = Cursors.exhaust(inputCur);
    }

    /// @notice Validate and consume all remaining state blocks with key.
    /// @dev Empty streams pass. Validates the requested key regardless of descriptor
    /// declarations; close still rejects any source bytes left unread.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param key Block key.
    /// @return stateCur Clean calldata cursor over the STATE payload.
    function takeState(Execution memory exec, bytes4 key) internal pure returns (uint stateCur) {
        stateCur = exec.state;
        stateCur.expectRun(key);
        exec.state = Cursors.exhaust(stateCur);
    }

    /// @notice Validate and consume all remaining state blocks with an exact header.
    /// @dev Shares takeState's empty-stream behavior; descriptor declarations do not affect validation.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param header Right-aligned 8-byte block header containing the key and exact payload size.
    /// @return stateCur Clean calldata cursor over the STATE payload.
    function takeStateFixed(Execution memory exec, uint header) internal pure returns (uint stateCur) {
        stateCur = exec.state;
        stateCur.expectRunFixed(header);
        exec.state = Cursors.exhaust(stateCur);
    }

    /// @notice Validate and consume the remaining state as BALANCE blocks.
    /// @dev Returns a clean stream cursor; shares takeStateFixed's lane behavior.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return stateCur Clean calldata cursor over the STATE payload.
    function takeBalances(Execution memory exec) internal pure returns (uint stateCur) {
        return takeStateFixed(exec, Headers.Balance);
    }

    /// @notice Consume one input block and return its payload as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param spec Packed block specification or named lane.
    /// @return payloadCur Clean calldata cursor over the payload.
    function unpack(Execution memory exec, uint spec) internal pure returns (uint payloadCur) {
        (payloadCur, exec.input) = exec.input.unpack(spec);
    }

    /// @notice Consume one input block and return its payload as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param key Block key.
    /// @return payloadCur Clean calldata cursor over the payload.
    function unpack(Execution memory exec, bytes4 key) internal pure returns (uint payloadCur) {
        (payloadCur, exec.input) = exec.input.unpack(key);
    }

    /// @notice Consume one input block and return its payload as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param header Right-aligned 8-byte block header containing the key and exact payload size.
    /// @return payloadCur Clean calldata cursor over the payload.
    function unpackFixed(Execution memory exec, uint header) internal pure returns (uint payloadCur) {
        (payloadCur, exec.input) = exec.input.unpackFixed(header);
    }

    /// @notice Consume the entire input as one matching block and return its payload as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param spec Packed block specification or named lane.
    /// @return payloadCur Clean calldata cursor over the payload.
    function unpackExact(Execution memory exec, uint spec) internal pure returns (uint payloadCur) {
        payloadCur = exec.input.unpackExact(spec);
        exhaustInput(exec);
    }

    /// @notice Consume the entire input as one exact-header block and return its payload.
    /// @dev Delegates validation to Blocks; returns a clean child and preserves input metadata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param header Right-aligned 8-byte block header containing the key and exact payload size.
    /// @return payloadCur Clean calldata cursor over the payload.
    function unpackFixedExact(Execution memory exec, uint header) internal pure returns (uint payloadCur) {
        payloadCur = exec.input.unpackFixedExact(header);
        exhaustInput(exec);
    }

    /// @notice Consume a LIST and return its clean payload cursor.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return itemsCur Clean calldata cursor over the list payload.
    function unpackList(Execution memory exec) internal pure returns (uint itemsCur) {
        (itemsCur, exec.input) = exec.input.unpackList();
    }

    /// @notice Consume a custom list and return its clean payload cursor.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param spec Packed block specification or named lane.
    /// @return itemsCur Clean calldata cursor over the list payload.
    function unpackList(Execution memory exec, uint spec) internal pure returns (uint itemsCur) {
        return unpack(exec, spec);
    }

    // Raw input navigation.

    /// @notice Advance input by a raw byte count and return its previous absolute position.
    /// @dev Validates containment once; no block header or schema is inspected.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param amount Number of source bytes to consume.
    /// @return abs Absolute calldata position of the selected bytes.
    function advance(Execution memory exec, uint amount) internal pure returns (uint abs) {
        (abs, exec.input) = Cursors.enter(exec.input, amount);
    }

    // -------------------------------------------------------------------------
    // Expectations
    // -------------------------------------------------------------------------

    /// @notice Consume one TRUST from state and check that it vouches for `id`.
    /// @dev Unlike the input expectations, TRUST is state. Reverts UnexpectedValue on a mismatch.
    /// @param exec Execution whose state cursor is advanced by one TRUST block.
    /// @param id Expected trusted identifier, for example an asset the command already knows.
    function expectTrust(Execution memory exec, uint id) internal pure {
        exec.state = exec.state.expectTrust(id);
    }

    /// @notice Consume one TRUST from state and check that it vouches for the word identifier `id`.
    /// @dev Same check as the `uint` overload, for `bytes32` IDs such as assets. Reverts UnexpectedValue on a mismatch.
    /// @param exec Execution whose state cursor is advanced by one TRUST block.
    /// @param id Expected trusted identifier as a word, for example an asset the command already knows.
    function expectTrust(Execution memory exec, bytes32 id) internal pure {
        exec.state = exec.state.expectTrust(id);
    }

    /// @notice Consume one LIMITS input and check final quantities directly against calldata.
    /// @param exec Execution whose input cursor is bounded and advanced by one block.
    /// @param amount Final asset amount, checked against the inclusive minimum.
    /// @param debt Final debt, checked against the literal inclusive maximum.
    function expectLimits(Execution memory exec, uint amount, uint debt) internal pure {
        exec.input = exec.input.expectLimits(amount, debt);
    }

    /// @notice Consume one BALANCE_CONSTRAINTS input and check an asset and amount directly against calldata.
    /// @dev Validates the header and containment once before asset and quantity checks.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    function expectBalanceConstraints(Execution memory exec, bytes32 asset, uint amount) internal pure {
        exec.input = exec.input.expectBalanceConstraints(asset, amount);
    }

    /// @notice Consume one POSITION_CONSTRAINTS input and check it directly against a position.
    /// @dev Validates the header and containment once before identifiers,
    /// and inclusive limits. Does not validate the position's counterparty.
    /// @param exec Execution whose input cursor is advanced by one POSITION_CONSTRAINTS block.
    /// @param position Position whose identifiers and full-width quantities are checked.
    function expectPositionConstraints(Execution memory exec, Position memory position) internal pure {
        exec.input = exec.input.expectPositionConstraints(position);
    }

    // -------------------------------------------------------------------------
    // Fixed-width block decoding
    // -------------------------------------------------------------------------

    /// @notice Decode one fixed 32-byte payload from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @param spec Expected fixed block specification.
    /// @return value Decoded payload word.
    function unpack32(Execution memory exec, uint spec) internal pure returns (bytes32 value) {
        (value, exec.input) = exec.input.unpack32(Specs.key(spec));
    }

    /// @notice Decode and consume one ACCOUNT block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return account Decoded account identifier.
    function unpackAccount(Execution memory exec) internal pure returns (bytes32 account) {
        (account, exec.input) = exec.input.unpackAccount();
    }

    /// @notice Decode and consume one ASSET block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return asset Decoded asset identifier.
    function unpackAsset(Execution memory exec) internal pure returns (bytes32 asset) {
        (asset, exec.input) = exec.input.unpackAsset();
    }

    /// @notice Decode and consume one NODE block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return node Decoded node identifier.
    function unpackNode(Execution memory exec) internal pure returns (uint node) {
        (node, exec.input) = exec.input.unpackNode();
    }

    /// @notice Decode and consume one ENTITY block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return entity Decoded entity identifier.
    function unpackEntity(Execution memory exec) internal pure returns (uint entity) {
        (entity, exec.input) = exec.input.unpackEntity();
    }

    /// @notice Decode and consume one TRUST block from state.
    /// @dev TRUST is state, so it is never read from user-supplied input.
    /// @param exec Execution whose state cursor is advanced.
    /// @return id Trusted identifier vouched for by the producing commander.
    function unpackTrust(Execution memory exec) internal pure returns (uint id) {
        (id, exec.state) = exec.state.unpackTrust();
    }

    /// @notice Decode and consume one LIMITS block.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return limits Packed inclusive minimum (high 128 bits) and maximum (low 128 bits); meaning is context-dependent.
    function unpackLimits(Execution memory exec) internal pure returns (uint limits) {
        (limits, exec.input) = exec.input.unpackLimits();
    }

    /// @notice Decode and consume one scalar AMOUNT block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return amount Full-width amount; the consumer defines its unit.
    function unpackAmount(Execution memory exec) internal pure returns (uint amount) {
        (amount, exec.input) = exec.input.unpackAmount();
    }

    /// @notice Decode and consume one ASSET_AMOUNT block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackAssetAmount(Execution memory exec) internal pure returns (bytes32 asset, uint amount) {
        (asset, amount, exec.input) = exec.input.unpackAssetAmount();
    }

    /// @notice Decode one ASSET_AMOUNT block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded asset and amount.
    function unpackAssetAmountValue(Execution memory exec) internal pure returns (AssetAmount memory value) {
        (value.asset, value.amount) = unpackAssetAmount(exec);
    }

    // Dedicated state block decoding

    /// @notice Decode and consume one BALANCE block from state.
    /// @dev Blocks validates the exact header before containment and advances once.
    /// @param exec Execution whose state cursor is advanced.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded balance amount.
    function unpackBalance(Execution memory exec) internal pure returns (bytes32 asset, uint amount) {
        (asset, amount, exec.state) = exec.state.unpackBalance();
    }

    /// @notice Decode and consume one BALANCE block from state into its structured value.
    /// @param exec Execution whose state cursor is advanced.
    /// @return value Decoded asset and balance amount.
    function unpackBalanceValue(Execution memory exec) internal pure returns (AssetAmount memory value) {
        (value.asset, value.amount) = unpackBalance(exec);
    }

    /// @notice Decode and consume one ASSET_LIABILITY block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return asset Decoded asset identifier.
    /// @return liability Decoded liability identifier.
    function unpackAssetLiability(Execution memory exec) internal pure returns (bytes32 asset, bytes32 liability) {
        (asset, liability, exec.input) = exec.input.unpackAssetLiability();
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
        (account, asset, exec.input) = exec.input.unpackAccountAsset();
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
        (host, asset, exec.input) = exec.input.unpackHostAsset();
    }

    /// @notice Decode one HOST_ASSET block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded host and asset.
    function unpackHostAssetValue(Execution memory exec) internal pure returns (HostAsset memory value) {
        (value.host, value.asset) = unpackHostAsset(exec);
    }

    /// @notice Decode one PIPELINE block from input and advance the input cursor.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return account Account identifier.
    /// @return budget Native-value budget, in wei.
    function unpackPipeline(Execution memory exec) internal pure returns (bytes32 account, uint budget) {
        (account, budget, exec.input) = exec.input.unpackPipeline();
    }

    /// @notice Decode and consume one BOOTSTRAP block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return budget Minimum native credit to retain after funding requested balances.
    /// @return balancesCur Cursor over the ASSET_AMOUNT blocks inside the balances list.
    function unpackBootstrap(Execution memory exec) internal pure returns (uint budget, uint balancesCur) {
        (budget, balancesCur, exec.input) = exec.input.unpackBootstrap();
    }

    /// @notice Decode and consume one VOUCH block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return budget Minimum native credit to retain after vouching.
    /// @return idsCur Cursor over the ENTITY blocks inside the ids list.
    function unpackVouch(Execution memory exec) internal pure returns (uint budget, uint idsCur) {
        (budget, idsCur, exec.input) = exec.input.unpackVouch();
    }

    /// @notice Decode and consume one ALLOCATION block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackAllocation(Execution memory exec) internal pure returns (uint host, bytes32 asset, uint amount) {
        (host, asset, amount, exec.input) = exec.input.unpackAllocation();
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
        (host, asset, amount, exec.input) = exec.input.unpackAllowance();
    }

    /// @notice Decode one ALLOWANCE block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded host, asset, and allowance amount.
    function unpackAllowanceValue(Execution memory exec) internal pure returns (HostAmount memory value) {
        (value.host, value.asset, value.amount) = unpackAllowance(exec);
    }

    /// @notice Decode and consume one CUSTODY block from state.
    /// @param exec Execution whose state cursor is advanced.
    /// @return host Decoded host identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded custody amount.
    function unpackCustody(Execution memory exec) internal pure returns (uint host, bytes32 asset, uint amount) {
        (host, asset, amount, exec.state) = exec.state.unpackCustody();
    }

    /// @notice Decode and consume one CUSTODY block from state into its structured value.
    /// @param exec Execution whose state cursor is advanced.
    /// @return value Decoded host, asset, and custody amount.
    function unpackCustodyValue(Execution memory exec) internal pure returns (HostAmount memory value) {
        (value.host, value.asset, value.amount) = unpackCustody(exec);
    }

    /// @notice Decode and consume one PAYOUT block from state.
    /// @dev Performs no recipient validation; a zero recipient means burn.
    /// @param exec Execution whose state cursor is advanced.
    /// @return recipient Decoded recipient account identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded payout amount.
    function unpackPayout(Execution memory exec) internal pure returns (bytes32 recipient, bytes32 asset, uint amount) {
        (recipient, asset, amount, exec.state) = exec.state.unpackPayout();
    }

    /// @notice Decode and consume one ACCOUNT_BALANCE block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackAccountBalance(
        Execution memory exec
    ) internal pure returns (bytes32 account, bytes32 asset, uint amount) {
        (account, asset, amount, exec.input) = exec.input.unpackAccountBalance();
    }

    /// @notice Decode one ACCOUNT_BALANCE block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded account, asset, and amount.
    function unpackAccountBalanceValue(Execution memory exec) internal pure returns (AccountBalance memory value) {
        (value.account, value.asset, value.amount) = unpackAccountBalance(exec);
    }

    /// @notice Decode and consume one ACCOUNT_AMOUNT block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    /// @return amount Decoded amount.
    function unpackAccountAmount(
        Execution memory exec
    ) internal pure returns (bytes32 account, bytes32 asset, uint amount) {
        (account, asset, amount, exec.input) = exec.input.unpackAccountAmount();
    }

    /// @notice Decode one ACCOUNT_AMOUNT block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded account, asset, and amount.
    function unpackAccountAmountValue(Execution memory exec) internal pure returns (AccountAmount memory value) {
        (value.account, value.asset, value.amount) = unpackAccountAmount(exec);
    }

    /// @notice Decode and consume one HOST_ACCOUNT_ASSET block from input.
    /// @param exec Execution whose input cursor is advanced.
    /// @return host Decoded host identifier.
    /// @return account Decoded account identifier.
    /// @return asset Decoded asset identifier.
    function unpackHostAccountAsset(
        Execution memory exec
    ) internal pure returns (uint host, bytes32 account, bytes32 asset) {
        (host, account, asset, exec.input) = exec.input.unpackHostAccountAsset();
    }

    /// @notice Decode one HOST_ACCOUNT_ASSET block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded host, account, and asset.
    function unpackHostAccountAssetValue(Execution memory exec) internal pure returns (HostAccountAsset memory value) {
        (value.host, value.account, value.asset) = unpackHostAccountAsset(exec);
    }

    /// @notice Decode and consume one BALANCE_CONSTRAINTS input without enforcing its bounds.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return value Decoded BalanceConstraints value in independent memory.
    function unpackBalanceConstraints(Execution memory exec) internal pure returns (BalanceConstraints memory value) {
        (value, exec.input) = exec.input.unpackBalanceConstraints();
    }

    /// @notice Decode and consume one QUOTE_REQUEST input as scalar values.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return asset Asset identifier.
    /// @return amount Quantity in the asset's native units.
    /// @return liability Liability asset identifier.
    function unpackQuoteRequest(Execution memory exec)
        internal pure returns (bytes32 asset, uint amount, bytes32 liability)
    {
        (asset, amount, liability, exec.input) = exec.input.unpackQuoteRequest();
    }

    /// @notice Decode and consume one QUOTE input with full-width asset and liability quantities.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return asset Asset identifier.
    /// @return amount Quantity in the asset's native units.
    /// @return liability Liability asset identifier.
    /// @return debt Quantity in the liability's native units.
    function unpackQuote(
        Execution memory exec
    ) internal pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt) {
        (asset, amount, liability, debt, exec.input) = exec.input.unpackQuote();
    }

    /// @notice Decode one QUOTE into its structured value.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return quote Decoded Quote value in independent memory.
    function unpackQuoteValue(Execution memory exec) internal pure returns (Quote memory quote) {
        (quote.asset, quote.amount, quote.liability, quote.debt) = unpackQuote(exec);
    }

    /// @notice Decode POSITION_CONSTRAINTS with exact denominations and inclusive full-width bounds.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return value Decoded PositionConstraints value in independent memory.
    function unpackPositionConstraints(Execution memory exec) internal pure returns (PositionConstraints memory value) {
        (value, exec.input) = exec.input.unpackPositionConstraints();
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
        (asset, amount, liability, debt, counterparty, exec.state) = exec.state.unpackPosition();
    }

    /// @notice Decode and consume one POSITION block from state into its structured value.
    /// @param exec Execution whose state cursor is advanced.
    /// @return value Decoded asset and liability position.
    function unpackPositionValue(Execution memory exec) internal pure returns (Position memory value) {
        (value.asset, value.amount, value.liability, value.debt, value.counterparty) = unpackPosition(exec);
    }

    /// @notice Decode and consume one BOOKING input block into independent memory.
    /// @dev Validates both legs before advancing input; accounts follow caller policy.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return value Decoded Booking value in independent memory.
    function unpackBooking(Execution memory exec) internal pure returns (Booking memory value) {
        (value, exec.input) = exec.input.unpackBooking();
    }

    // -------------------------------------------------------------------------
    // Dynamic block decoding
    // -------------------------------------------------------------------------

    /// @notice Decode BYTES and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return payloadCur Clean calldata cursor over the payload.
    function unpackBytes(Execution memory exec) internal pure returns (uint payloadCur) {
        (payloadCur, exec.input) = exec.input.unpackBytes();
    }

    /// @notice Decode STRING and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return textCur Clean calldata cursor over the string payload.
    function unpackString(Execution memory exec) internal pure returns (uint textCur) {
        (textCur, exec.input) = exec.input.unpackString();
    }

    /// @notice Decode RELAY and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return inputCur Clean calldata cursor over the INPUT payload.
    /// @return stepsCur Clean calldata cursor over the continuation STEP stream.
    function unpackRelay(Execution memory exec) internal pure returns (uint inputCur, uint stepsCur) {
        (inputCur, stepsCur, exec.input) = exec.input.unpackRelay();
    }

    /// @notice Decode SCHEMA and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return spec Packed block specification or named lane.
    /// @return bodyCur Clean calldata cursor over the schema STRING payload.
    function unpackSchema(Execution memory exec) internal pure returns (uint spec, uint bodyCur) {
        (spec, bodyCur, exec.input) = exec.input.unpackSchema();
    }

    /// @notice Decode CONTEXT and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return account Account identifier.
    /// @return stateCur Clean calldata cursor over the STATE payload.
    /// @return inputCur Clean calldata cursor over the INPUT payload.
    function unpackContext(
        Execution memory exec
    ) internal pure returns (bytes32 account, uint stateCur, uint inputCur) {
        (account, stateCur, inputCur, exec.input) = exec.input.unpackContext();
    }

    /// @notice Decode STEP and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return cmd Command node identifier.
    /// @return value Native value assigned to the operation, in wei.
    /// @return inputCur Clean calldata cursor over the INPUT payload.
    function unpackStep(Execution memory exec) internal pure returns (uint cmd, uint value, uint inputCur) {
        (cmd, value, inputCur, exec.input) = exec.input.unpackStep();
    }

    /// @notice Consume SWAP input and return its fixed fields and LIST payload cursor.
    /// @dev Validates structural encoding; the caller validates hop blocks and route semantics.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return asset Asset identifier.
    /// @return amount Quantity in the asset's native units.
    /// @return hopsCur Clean calldata cursor over the hop LIST payload.
    function unpackSwap(Execution memory exec) internal pure returns (bytes32 asset, uint amount, uint hopsCur) {
        (asset, amount, hopsCur, exec.input) = exec.input.unpackSwap();
    }

    /// @notice Decode CALL and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return target Target node identifier.
    /// @return value Native value assigned to the operation, in wei.
    /// @return payloadCur Clean calldata cursor over the payload.
    function unpackCall(Execution memory exec) internal pure returns (uint target, uint value, uint payloadCur) {
        (target, value, payloadCur, exec.input) = exec.input.unpackCall();
    }

    /// @notice Decode DISPATCH and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return portal Transport portal node identifier.
    /// @return resources Transport resource descriptor.
    /// @return payloadCur Clean calldata cursor over the payload.
    function unpackDispatch(
        Execution memory exec
    ) internal pure returns (uint portal, uint resources, uint payloadCur) {
        (portal, resources, payloadCur, exec.input) = exec.input.unpackDispatch();
    }

    /// @notice Decode RECOVER and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return handler Recovery handler node identifier.
    /// @return value Native value assigned to the operation, in wei.
    /// @return key Forwarding or recovery lookup key.
    /// @return witnessCur Clean calldata cursor over the recovery witness payload.
    function unpackRecover(
        Execution memory exec
    ) internal pure returns (uint handler, uint value, bytes32 key, uint witnessCur) {
        (handler, value, key, witnessCur, exec.input) = exec.input.unpackRecover();
    }

    // -------------------------------------------------------------------------
    // Output writing
    // -------------------------------------------------------------------------

    /// @notice Reserve output bytes and return their absolute memory address.
    /// @dev Requires an opened execution. Fill all reserved bytes before another
    /// reservation or finalization. The encoder retains one scratch word beyond
    /// capacity for writes that extend beyond the logical reservation.
    /// @param exec Execution whose output writer and buffer are updated.
    /// @param size Logical number of bytes appended.
    /// @return abs Absolute address of the reserved output range.
    function reserve(Execution memory exec, uint size) internal pure returns (uint abs) {
        (exec.buffer, abs, exec.output) = exec.output.reserve(exec.buffer, size);
    }

    /// @notice Append an ACCOUNT block to execution output.
    /// @param exec Execution receiving the block.
    /// @param account Account identifier to encode.
    function outputAccount(Execution memory exec, bytes32 account) internal pure {
        (exec.buffer, exec.output) = exec.output.writeAccount(exec.buffer, account);
    }

    /// @notice Append an ASSET block to execution output.
    /// @param exec Execution receiving the block.
    /// @param asset Asset identifier to encode.
    function outputAsset(Execution memory exec, bytes32 asset) internal pure {
        (exec.buffer, exec.output) = exec.output.writeAsset(exec.buffer, asset);
    }

    /// @notice Append a NODE block to execution output.
    /// @param exec Execution receiving the block.
    /// @param node Node identifier to encode.
    function outputNode(Execution memory exec, uint node) internal pure {
        (exec.buffer, exec.output) = exec.output.writeNode(exec.buffer, node);
    }

    /// @notice Append a ENTITY block to execution output.
    /// @param exec Execution receiving the block.
    /// @param entity Entity identifier to encode.
    function outputEntity(Execution memory exec, uint entity) internal pure {
        (exec.buffer, exec.output) = exec.output.writeEntity(exec.buffer, entity);
    }

    /// @notice Append a TRUST block to execution output.
    /// @dev Performs no registry check; only a commander that verified `id` should emit it.
    /// @param exec Execution receiving the block.
    /// @param id Trusted identifier to encode.
    function outputTrust(Execution memory exec, uint id) internal pure {
        (exec.buffer, exec.output) = exec.output.writeTrust(exec.buffer, id);
    }

    /// @notice Append a STATUS block to execution output.
    /// @param exec Execution receiving the block.
    /// @param code Status code to encode.
    function outputStatus(Execution memory exec, uint code) internal pure {
        (exec.buffer, exec.output) = exec.output.writeStatus(exec.buffer, code);
    }

    /// @notice Append a scalar AMOUNT block to execution output.
    /// @param exec Execution receiving the block.
    /// @param amount Full-width amount to encode.
    function outputAmount(Execution memory exec, uint amount) internal pure {
        (exec.buffer, exec.output) = exec.output.writeAmount(exec.buffer, amount);
    }

    /// @notice Append an ASSET_AMOUNT block to execution output.
    /// @param exec Execution receiving the block.
    /// @param asset Asset identifier to encode.
    /// @param amount Asset amount to encode.
    function outputAssetAmount(Execution memory exec, bytes32 asset, uint amount) internal pure {
        (exec.buffer, exec.output) = exec.output.writeAssetAmount(exec.buffer, asset, amount);
    }

    /// @notice Append a structured ASSET_AMOUNT value to execution output.
    /// @param exec Execution receiving the block.
    /// @param value Structured asset amount to encode.
    function outputAssetAmount(Execution memory exec, AssetAmount memory value) internal pure {
        outputAssetAmount(exec, value.asset, value.amount);
    }

    /// @notice Append PIPELINE to output without emitting a log or changing execution context.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param account Account identifier.
    /// @param budget Native-value budget, in wei.
    function outputPipeline(Execution memory exec, bytes32 account, uint budget) internal pure {
        (exec.buffer, exec.output) = exec.output.writePipeline(exec.buffer, account, budget);
    }

    /// @notice Append a BALANCE block to execution output.
    /// @param exec Execution receiving the block.
    /// @param asset Asset identifier to encode.
    /// @param amount Balance amount to encode.
    function outputBalance(Execution memory exec, bytes32 asset, uint amount) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBalance(exec.buffer, asset, amount);
    }

    /// @notice Append a structured BALANCE value to execution output.
    /// @param exec Execution receiving the block.
    /// @param value Structured asset balance to encode.
    function outputBalance(Execution memory exec, AssetAmount memory value) internal pure {
        Encoder.writeBalanceAt(reserve(exec, Sizes.Balance), value);
    }

    /// @notice Append a LIMITS block with a packed inclusive minimum and maximum.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param limits Packed inclusive minimum (high 128 bits) and maximum (low 128 bits); meaning is context-dependent.
    function outputLimits(Execution memory exec, uint limits) internal pure {
        (exec.buffer, exec.output) = exec.output.writeLimits(exec.buffer, limits);
    }

    /// @notice Append a scalar QUOTE_REQUEST block to execution output.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param liability Liability asset identifier.
    function outputQuoteRequest(Execution memory exec, bytes32 asset, uint amount, bytes32 liability) internal pure {
        (exec.buffer, exec.output) = exec.output.writeQuoteRequest(exec.buffer, asset, amount, liability);
    }

    /// @notice Append a QUOTE with full-width asset and liability quantities.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param liability Liability asset identifier.
    /// @param debt Quantity in the liability's native units.
    function outputQuote(
        Execution memory exec,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) internal pure {
        (exec.buffer, exec.output) = exec.output.writeQuote(exec.buffer, asset, amount, liability, debt);
    }

    /// @notice Append a structured QUOTE.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param quote Quoted asset and liability quantities.
    function outputQuote(Execution memory exec, Quote memory quote) internal pure {
        outputQuote(exec, quote.asset, quote.amount, quote.liability, quote.debt);
    }

    /// @notice Append a POSITION block to execution output.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param liability Liability asset identifier.
    /// @param debt Quantity in the liability's native units.
    /// @param counterparty Settlement counterparty account, or zero for Rootzero.
    function outputPosition(
        Execution memory exec,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt,
        bytes32 counterparty
    ) internal pure {
        (exec.buffer, exec.output) = exec.output.writePosition(
            exec.buffer,
            asset,
            amount,
            liability,
            debt,
            counterparty
        );
    }

    /// @notice Append a structured POSITION value to execution output.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param value Position fields used by this operation.
    function outputPosition(Execution memory exec, Position memory value) internal pure {
        Encoder.writePositionAt(reserve(exec, Sizes.Position), value);
    }

    /// @notice Append one structured BOOKING output block.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param value Booking fields used by this operation.
    function outputBooking(Execution memory exec, Booking memory value) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBooking(exec.buffer, value);
    }

    /// @notice Append an ACCOUNT_ASSET block to execution output.
    /// @param exec Execution receiving the block.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    function outputAccountAsset(Execution memory exec, bytes32 account, bytes32 asset) internal pure {
        (exec.buffer, exec.output) = exec.output.writeAccountAsset(exec.buffer, account, asset);
    }

    /// @notice Append an ASSET_LIABILITY block to execution output.
    /// @param exec Execution receiving the block.
    /// @param asset Asset identifier to encode.
    /// @param liability Liability identifier to encode.
    function outputAssetLiability(Execution memory exec, bytes32 asset, bytes32 liability) internal pure {
        (exec.buffer, exec.output) = exec.output.writeAssetLiability(exec.buffer, asset, liability);
    }

    /// @notice Append a structured ASSET_LIABILITY value to execution output.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param value AssetLiability fields used by this operation.
    function outputAssetLiability(Execution memory exec, AssetLiability memory value) internal pure {
        outputAssetLiability(exec, value.asset, value.liability);
    }

    /// @notice Append a HOST_ASSET block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    function outputHostAsset(Execution memory exec, uint host, bytes32 asset) internal pure {
        (exec.buffer, exec.output) = exec.output.writeHostAsset(exec.buffer, host, asset);
    }

    /// @notice Append an ALLOCATION block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Allocation amount to encode.
    function outputAllocation(Execution memory exec, uint host, bytes32 asset, uint amount) internal pure {
        (exec.buffer, exec.output) = exec.output.writeAllocation(exec.buffer, host, asset, amount);
    }

    /// @notice Append an ALLOWANCE block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Allowance amount to encode.
    function outputAllowance(Execution memory exec, uint host, bytes32 asset, uint amount) internal pure {
        (exec.buffer, exec.output) = exec.output.writeAllowance(exec.buffer, host, asset, amount);
    }

    /// @notice Append a CUSTODY block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Custody amount to encode.
    function outputCustody(Execution memory exec, uint host, bytes32 asset, uint amount) internal pure {
        (exec.buffer, exec.output) = exec.output.writeCustody(exec.buffer, host, asset, amount);
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

    /// @notice Append a PAYOUT block to execution output.
    /// @param exec Execution receiving the block.
    /// @param recipient Recipient account identifier to encode; zero means burn.
    /// @param asset Asset identifier to encode.
    /// @param amount Payout amount to encode.
    function outputPayout(Execution memory exec, bytes32 recipient, bytes32 asset, uint amount) internal pure {
        (exec.buffer, exec.output) = exec.output.writePayout(exec.buffer, recipient, asset, amount);
    }

    /// @notice Append an ACCOUNT_BALANCE block to execution output.
    /// @param exec Execution receiving the block.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Account amount to encode.
    function outputAccountBalance(Execution memory exec, bytes32 account, bytes32 asset, uint amount) internal pure {
        (exec.buffer, exec.output) = exec.output.writeAccountBalance(exec.buffer, account, asset, amount);
    }

    /// @notice Append a structured ACCOUNT_BALANCE value to execution output.
    /// @param exec Execution receiving the block.
    /// @param value Structured account asset amount to encode.
    function outputAccountBalance(Execution memory exec, AccountBalance memory value) internal pure {
        outputAccountBalance(exec, value.account, value.asset, value.amount);
    }

    /// @notice Append an ACCOUNT_AMOUNT block to execution output.
    /// @param exec Execution receiving the block.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    /// @param amount Account amount to encode.
    function outputAccountAmount(Execution memory exec, bytes32 account, bytes32 asset, uint amount) internal pure {
        (exec.buffer, exec.output) = exec.output.writeAccountAmount(exec.buffer, account, asset, amount);
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
        (exec.buffer, exec.output) = exec.output.writeHostAmount(exec.buffer, host, asset, amount);
    }

    /// @notice Append a HOST_ACCOUNT_ASSET block to execution output.
    /// @param exec Execution receiving the block.
    /// @param host Host identifier to encode.
    /// @param account Account identifier to encode.
    /// @param asset Asset identifier to encode.
    function outputHostAccountAsset(Execution memory exec, uint host, bytes32 account, bytes32 asset) internal pure {
        (exec.buffer, exec.output) = exec.output.writeHostAccountAsset(exec.buffer, host, account, asset);
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
        (exec.buffer, exec.output) = exec.output.writeHostAccountAmount(exec.buffer, host, account, asset, amount);
    }

    /// @notice Append a LIST block to execution output.
    /// @param exec Execution receiving the block.
    /// @param value Encoded list payload.
    function outputList(Execution memory exec, bytes memory value) internal pure {
        (exec.buffer, exec.output) = exec.output.writeList(exec.buffer, value);
    }

    /// @notice Append a BYTES block to execution output.
    /// @param exec Execution receiving the block.
    /// @param value Byte payload to encode.
    function outputBytes(Execution memory exec, bytes memory value) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBytes(exec.buffer, value);
    }

    /// @notice Append a STRING block to execution output.
    /// @param exec Execution receiving the block.
    /// @param value String payload to encode.
    function outputString(Execution memory exec, string memory value) internal pure {
        (exec.buffer, exec.output) = exec.output.writeString(exec.buffer, bytes(value));
    }

    /// @notice Append a STEP block to execution output.
    /// @param exec Execution receiving the block.
    /// @param cmd Command identifier to encode.
    /// @param value Native value to encode.
    /// @param input Command input to encode.
    function outputStep(Execution memory exec, uint cmd, uint value, bytes memory input) internal pure {
        (exec.buffer, exec.output) = exec.output.writeStepWrap(exec.buffer, cmd, value, input);
    }

    /// @notice Append SWAP output, wrapping memory ASSET blocks in LIST.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param hops ASSET hop block stream, excluding the LIST child header.
    function outputSwap(Execution memory exec, bytes32 asset, uint amount, bytes memory hops) internal pure {
        (exec.buffer, exec.output) = exec.output.writeSwapWrap(exec.buffer, asset, amount, hops);
    }

    /// @notice Append SWAP output from a complete validated LIST child cursor.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param hopsCur Validated calldata cursor over the complete LIST child, including its header.
    function outputSwap(Execution memory exec, bytes32 asset, uint amount, uint hopsCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeSwap(exec.buffer, asset, amount, hopsCur);
    }

    /// @notice Append SWAP output by wrapping a validated ASSET stream cursor in LIST.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
    /// @param hopsCur Validated calldata cursor over the LIST payload, excluding its header.
    function outputSwapWrap(Execution memory exec, bytes32 asset, uint amount, uint hopsCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeSwapWrap(exec.buffer, asset, amount, hopsCur);
    }

    /// @notice Append a CALL block to execution output.
    /// @param exec Execution receiving the block.
    /// @param target Call target to encode.
    /// @param value Full-width native value to encode.
    /// @param payload Call payload to encode.
    function outputCall(Execution memory exec, uint target, uint value, bytes memory payload) internal pure {
        (exec.buffer, exec.output) = exec.output.writeCallWrap(exec.buffer, target, value, payload);
    }

    /// @notice Append a RELAY block to execution output.
    /// @param exec Execution receiving the block.
    /// @param input Relay input to encode.
    /// @param steps Remaining pipeline steps to encode.
    function outputRelay(Execution memory exec, bytes memory input, bytes memory steps) internal pure {
        (exec.buffer, exec.output) = exec.output.writeRelayWrap(exec.buffer, input, steps);
    }

    /// @notice Append a DISPATCH block to execution output.
    /// @param exec Execution receiving the block.
    /// @param portal Destination portal to encode.
    /// @param resources Packed resources to encode.
    /// @param payload Dispatch payload to encode.
    function outputDispatch(Execution memory exec, uint portal, uint resources, bytes memory payload) internal pure {
        (exec.buffer, exec.output) = exec.output.writeDispatchWrap(exec.buffer, portal, resources, payload);
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
        (exec.buffer, exec.output) = exec.output.writeContextWrap(exec.buffer, account, state, input);
    }

    /// @notice Append a RECOVER block to execution output.
    /// @param exec Execution receiving the block.
    /// @param handler Recovery handler to encode.
    /// @param value Full-width native value to encode.
    /// @param recoverykey Recovery key to encode.
    /// @param witness Recovery witness to encode.
    function outputRecover(
        Execution memory exec,
        uint handler,
        uint value,
        bytes32 recoverykey,
        bytes memory witness
    ) internal pure {
        (exec.buffer, exec.output) = exec.output.writeRecoverWrap(exec.buffer, handler, value, recoverykey, witness);
    }

    /// @notice Append a SCHEMA block to execution output.
    /// @param exec Execution receiving the block.
    /// @param spec Block specification to encode.
    /// @param body Schema DSL string, optionally prefixed with `name:`.
    function outputSchema(Execution memory exec, uint spec, string memory body) internal pure {
        (exec.buffer, exec.output) = exec.output.writeSchemaWrap(exec.buffer, spec, bytes(body));
    }

    // -------------------------------------------------------------------------
    // Calldata cursor output helpers: complete blocks, then payload wrapping
    // -------------------------------------------------------------------------

    /// @notice Append BLOCK output using a complete validated block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param dataCur Validated calldata cursor over the complete block child, including its header.
    function outputBlock(Execution memory exec, uint dataCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBlock(exec.buffer, dataCur);
    }

    /// @notice Append LIST output using a complete validated block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param valueCur Validated calldata cursor over the complete LIST child, including its header.
    function outputList(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBlock(exec.buffer, valueCur);
    }

    /// @notice Append BYTES output using a complete validated block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param valueCur Validated calldata cursor over the complete BYTES child, including its header.
    function outputBytes(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBlock(exec.buffer, valueCur);
    }

    /// @notice Append STRING output using a complete validated block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param valueCur Validated calldata cursor over the complete STRING child, including its header.
    function outputString(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBlock(exec.buffer, valueCur);
    }

    /// @notice Append STEP output using a complete validated INPUT child block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param cmd Command node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param inputCur Validated calldata cursor over the complete INPUT child, including its header.
    function outputStep(Execution memory exec, uint cmd, uint value, uint inputCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeStep(exec.buffer, cmd, value, inputCur);
    }

    /// @notice Append CALL output using a complete validated BYTES child block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param target Target node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param payloadCur Validated calldata cursor over the complete BYTES child, including its header.
    function outputCall(Execution memory exec, uint target, uint value, uint payloadCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeCall(exec.buffer, target, value, payloadCur);
    }

    /// @notice Append DISPATCH output using a complete validated BYTES child block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param portal Transport portal node identifier.
    /// @param resources Transport resource descriptor.
    /// @param payloadCur Validated calldata cursor over the complete BYTES child, including its header.
    function outputDispatch(Execution memory exec, uint portal, uint resources, uint payloadCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeDispatch(exec.buffer, portal, resources, payloadCur);
    }

    /// @notice Append RELAY output using complete validated INPUT and BYTES child blocks.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param inputCur Validated calldata cursor over the complete INPUT child, including its header.
    /// @param stepsCur Validated calldata cursor over the complete BYTES child, including its header.
    function outputRelay(Execution memory exec, uint inputCur, uint stepsCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeRelay(exec.buffer, inputCur, stepsCur);
    }

    /// @notice Append CONTEXT output using complete validated STATE and INPUT child blocks.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param account Account identifier.
    /// @param stateCur Validated calldata cursor over the complete STATE child, including its header.
    /// @param inputCur Validated calldata cursor over the complete INPUT child, including its header.
    function outputContext(Execution memory exec, bytes32 account, uint stateCur, uint inputCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeContext(exec.buffer, account, stateCur, inputCur);
    }

    /// @notice Append RECOVER output using a complete validated BYTES child block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param handler Recovery handler node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param recoverykey Recovery lookup key.
    /// @param witnessCur Validated calldata cursor over the complete BYTES child, including its header.
    function outputRecover(
        Execution memory exec,
        uint handler,
        uint value,
        bytes32 recoverykey,
        uint witnessCur
    ) internal pure {
        (exec.buffer, exec.output) = exec.output.writeRecover(exec.buffer, handler, value, recoverykey, witnessCur);
    }

    /// @notice Append SCHEMA from a complete validated STRING block cursor.
    /// @dev Source is not advanced or revalidated; its range must belong to calldata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param spec Packed block specification or named lane.
    /// @param bodyCur Validated calldata cursor over the complete STRING child, including its header.
    function outputSchema(Execution memory exec, uint spec, uint bodyCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeSchema(exec.buffer, spec, bodyCur);
    }

    /// @notice Append a custom block to execution output by wrapping a validated calldata payload cursor.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param spec Packed block specification or named lane.
    /// @param dataCur Validated calldata cursor over the block payload, excluding its header.
    function outputBlockWrap(Execution memory exec, uint spec, uint dataCur) internal pure {
        Specs.validate(spec, Encoder.length(dataCur));
        (exec.buffer, exec.output) = exec.output.writeBlock(exec.buffer, Specs.key(spec), dataCur);
    }

    /// @notice Append a LIST block to execution output by wrapping a validated calldata payload cursor.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param valueCur Validated calldata cursor over the LIST payload, excluding its header.
    function outputListWrap(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeList(exec.buffer, valueCur);
    }

    /// @notice Append a BYTES block to execution output by wrapping a validated calldata payload cursor.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param valueCur Validated calldata cursor over the BYTES payload, excluding its header.
    function outputBytesWrap(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBytes(exec.buffer, valueCur);
    }

    /// @notice Append a STRING block to execution output by wrapping a validated calldata payload cursor.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param valueCur Validated calldata cursor over the STRING payload, excluding its header.
    function outputStringWrap(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeString(exec.buffer, valueCur);
    }

    /// @notice Append a STEP block to execution output by wrapping a validated input payload cursor in INPUT.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param cmd Command node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param inputCur Validated calldata cursor over the INPUT payload, excluding its header.
    function outputStepWrap(Execution memory exec, uint cmd, uint value, uint inputCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeStepWrap(exec.buffer, cmd, value, inputCur);
    }

    /// @notice Append a CALL block to execution output by wrapping a validated payload cursor in BYTES.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param target Target node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param payloadCur Validated calldata cursor over the BYTES payload, excluding its header.
    function outputCallWrap(Execution memory exec, uint target, uint value, uint payloadCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeCallWrap(exec.buffer, target, value, payloadCur);
    }

    /// @notice Append a DISPATCH block to execution output by wrapping a validated payload cursor in BYTES.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param portal Transport portal node identifier.
    /// @param resources Transport resource descriptor.
    /// @param payloadCur Validated calldata cursor over the BYTES payload, excluding its header.
    function outputDispatchWrap(Execution memory exec, uint portal, uint resources, uint payloadCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeDispatchWrap(exec.buffer, portal, resources, payloadCur);
    }

    /// @notice Append a RELAY block to execution output by wrapping validated payload cursors in INPUT and BYTES.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param inputCur Validated calldata cursor over the INPUT payload, excluding its header.
    /// @param stepsCur Validated calldata cursor over the BYTES payload, excluding its header.
    function outputRelayWrap(Execution memory exec, uint inputCur, uint stepsCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeRelayWrap(exec.buffer, inputCur, stepsCur);
    }

    /// @notice Append a CONTEXT block to execution output by wrapping validated payload cursors in STATE and INPUT.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param account Account identifier.
    /// @param stateCur Validated calldata cursor over the STATE payload, excluding its header.
    /// @param inputCur Validated calldata cursor over the INPUT payload, excluding its header.
    function outputContextWrap(Execution memory exec, bytes32 account, uint stateCur, uint inputCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeContextWrap(exec.buffer, account, stateCur, inputCur);
    }

    /// @notice Append a RECOVER block to execution output by wrapping a validated witness payload cursor in BYTES.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param handler Recovery handler node identifier.
    /// @param value Native value assigned to the operation, in wei.
    /// @param recoverykey Recovery lookup key.
    /// @param witnessCur Validated calldata cursor over the BYTES payload, excluding its header.
    function outputRecoverWrap(
        Execution memory exec,
        uint handler,
        uint value,
        bytes32 recoverykey,
        uint witnessCur
    ) internal pure {
        (exec.buffer, exec.output) = exec.output.writeRecoverWrap(exec.buffer, handler, value, recoverykey, witnessCur);
    }

    /// @notice Append SCHEMA from a payload cursor; adds the STRING header.
    /// @dev Source is not advanced or revalidated; its range must belong to calldata.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @param spec Packed block specification or named lane.
    /// @param bodyCur Validated calldata cursor over the STRING payload, excluding its header.
    function outputSchemaWrap(Execution memory exec, uint spec, uint bodyCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeSchemaWrap(exec.buffer, spec, bodyCur);
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
        unchecked {
            exec.budget -= value;
        }
        return value;
    }

    /// @notice Add trusted native value to the execution budget.
    /// @dev This updates accounting only. The caller must ensure the added value
    /// is backed by native value held by the host or otherwise made available.
    /// @param exec Mutable execution whose budget is credited.
    /// @param value Native value to add in wei.
    function addToBudget(Execution memory exec, uint value) internal pure {
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

    /// @notice Call a port with memory data and update the execution budget.
    /// @dev Debits value before calling and adds the returned trusted credit.
    /// The caller must authorize the selector/target and ensure credit is backed;
    /// this helper does not transfer ETH back.
    /// @param exec Mutable execution whose budget funds the call and receives credit.
    /// @param selector Selector of a `bytes -> (bytes, uint)` port.
    /// @param target Target contract address.
    /// @param value Native value to forward in wei.
    /// @param data Raw contents of the port's `bytes` argument.
    /// @param expectEmpty Whether the decoded output must be empty.
    /// @return out Decoded output bytes returned by the target.
    function rawCall(
        Execution memory exec,
        bytes4 selector,
        address target,
        uint value,
        bytes memory data,
        bool expectEmpty
    ) internal returns (bytes memory out) {
        if (value > exec.budget) revert InsufficientValue();
        unchecked {
            exec.budget -= value;
        }

        uint credit;
        (out, credit) = Calls.raw(selector, target, value, data, expectEmpty);
        exec.budget += credit;
    }

    /// @notice Call a port with a calldata cursor and update the execution budget.
    /// @dev Copies data directly from calldata. Debits value before calling and
    /// adds the returned trusted credit. The caller must authorize the selector/target
    /// and ensure credit is backed; this helper does not transfer ETH back.
    /// Requires current <= end <= calldatasize; ignores metadata and does not advance the cursor.
    /// @param exec Mutable execution whose budget funds the call and receives credit.
    /// @param selector Selector of a `bytes -> (bytes, uint)` port.
    /// @param target Target contract address.
    /// @param value Native value to forward in wei.
    /// @param dataCur Validated calldata cursor over the raw contents of the port's `bytes` argument.
    /// @param expectEmpty Whether the decoded output must be empty.
    /// @return out Decoded output bytes returned by the target.
    function rawCall(
        Execution memory exec,
        bytes4 selector,
        address target,
        uint value,
        uint dataCur,
        bool expectEmpty
    ) internal returns (bytes memory out) {
        if (value > exec.budget) revert InsufficientValue();
        unchecked {
            exec.budget -= value;
        }

        uint credit;
        (out, credit) = Calls.raw(selector, target, value, dataCur, expectEmpty);
        exec.budget += credit;
    }

    // -------------------------------------------------------------------------
    // Finalization
    // -------------------------------------------------------------------------

    /// @notice Require both execution sources to be consumed exactly.
    /// @dev Rejects remaining data and overshot cursors with UnconsumedData.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function expectEnd(Execution memory exec) internal pure {
        Cursors.expectEnd(exec.input);
        Cursors.expectEnd(exec.state);
    }

    /// @notice Finalize output without checking sources or changing the budget.
    /// @dev Ends the writer lifecycle. Caller must establish source consumption
    /// through a complete loop over valid cursors, expectEnd, or close.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return out Final output block stream.
    function finish(Execution memory exec) internal pure returns (bytes memory out) {
        // An unopened execution has no owned buffer to finalize in place.
        if (exec.buffer.length == 0) return Encoder.allocate(0);
        return Encoder.finish(exec.output, exec.buffer);
    }

    /// @notice Check consumption, finalize output, and return and clear the budget.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    /// @return output Final output block stream.
    /// @return credit Native value returned to the caller budget, in wei.
    function close(Execution memory exec) internal pure returns (bytes memory output, uint credit) {
        expectEnd(exec);
        output = finish(exec);
        credit = drainBudget(exec);
    }


}
