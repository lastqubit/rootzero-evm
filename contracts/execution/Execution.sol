// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Headers} from "../codec/Headers.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Keys, STATE_KEY, INPUT_KEY, CONTEXT_KEY} from "../codec/Keys.sol";
import {Logs} from "../codec/Logs.sol";
import {Specs, Sizes} from "../codec/Specs.sol";
import {Lanes} from "../codec/Lanes.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Budget} from "../core/Budget.sol";
import {Calls} from "../core/Calls.sol";
import {
    InsufficientValue,
    OutOfBounds,
    UnconsumedData,
    ValueOverflow,
    ZeroAmount,
    INVALID_BLOCK
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
    Booking,
    Tx
} from "../core/Types.sol";

/// @notice Mutable state shared across one endpoint execution.
/// @dev `input` and `state` are independent packed calldata cursors: current
/// position in bits 0-31 and exclusive end in bits 32-63. Higher bits are unused.
struct Execution {
    /// @dev Trusted active account; context decoding checks structure, not account format.
    /// Untrusted account input must be validated at entry before internal execution.
    bytes32 account;
    uint budget;
    uint input;
    uint state;
    /// @dev Packed output cursor: written offset in bits 0-31, capacity in bits 32-63.
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
    uint internal constant LogState = 1 << 1;
    uint internal constant LogInput = 1 << 2;
    uint internal constant LogOutput = 1 << 3;

    /// @notice Precompute allocation hints and lane-derived logging selections for execution.
    /// @dev Layout: [source key:4][source block size:4][output block size:4]
    /// [reserved:19][flags:1]. Sizes include headers and require 25 bits at maximum hint.
    /// Declared state takes precedence over input, even when supplied state is empty.
    /// Zero output size disables preallocation; no source reserves one output block.
    /// State/input/output are lanes: specs in the upper half, codes in the lower half.
    /// Nonzero lane codes select logging; endpoint behavior flags are independent.
    function describe(uint state, uint input, uint output) internal pure returns (uint descriptor) {
        bool stateSource = Specs.key(state) != bytes4(0);
        uint source = stateSource ? state : input;
        descriptor =
            (uint(uint32(Specs.key(source))) << 224) |
            (Specs.blockSize(source) << 192) |
            (Specs.blockSize(output) << 160) |
            (stateSource ? StateSource : 0) |
            (Lanes.codes(state) != 0 ? LogState : 0) |
            (Lanes.codes(input) != 0 ? LogInput : 0) |
            (Lanes.codes(output) != 0 ? LogOutput : 0);
    }

    /// @notice Log selected STATE/INPUT blocks from a freshly opened context.
    /// @dev Requires untouched cursors from openContext and its matching descriptor.
    /// Call before consuming either source. Includes each selected container header;
    /// both selected blocks are adjacent and copied together. Empty selected blocks
    /// retain their headers. Emits [id:32][blocks] without changing the execution.
    /// Input-only executions from openInput are not valid here.
    function logContext(Execution memory exec, uint id, uint descriptor) internal {
        if (descriptor & (LogState | LogInput) == 0) return;
        uint abs;
        uint size;
        // openContext proves both cursors follow their headers and share one
        // bounded context. The selected end cannot precede the selected header.
        // Execution layout: input at +64, state at +96. LogState is bit 1;
        // LogInput is bit 2. Select both addresses without per-lane branches.
        assembly ("memory-safe") {
            let startCur := mload(add(exec, add(64, shl(4, and(descriptor, LogState)))))
            let endCur := mload(add(exec, sub(96, shl(3, and(descriptor, LogInput)))))
            abs := sub(and(startCur, 0xffffffff), 8)
            size := sub(and(shr(32, endCur), 0xffffffff), abs)
        }
        Logs.copy(id, abs, size);
    }

    /// @notice Log raw input from a freshly opened input-only execution.
    /// @dev Requires untouched input from openInput and its matching descriptor.
    /// Call before consuming input. Nonzero input lane codes select emission;
    /// other lane selections are ignored. Emits [id:32][INPUT header][input],
    /// including the header for empty input. Creates the missing header in
    /// temporary memory; preserves all execution fields and the free-memory pointer.
    function logInput(Execution memory exec, uint id, uint descriptor) internal {
        if (descriptor & LogInput == 0) return;
        Logs.copyWrap(id, bytes4(uint32(INPUT_KEY)), exec.input);
    }

    /// @dev Capacity is only a hint; decoding validates the stream and buffers can grow.
    function outputCapacity(uint input, uint state, uint descriptor) private pure returns (uint capacity) {
        if (uint32(descriptor >> 160) == 0) return 0;
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

    /// @dev Scale an allocation hint with floor division before allocating.
    /// The unit ratio is an identity; Encoder.init checks the final uint32 limit.
    function scaledCapacity(uint capacity, uint numerator, uint denominator) private pure returns (uint) {
        if (denominator == 0) revert ZeroAmount();
        if (numerator == 1 && denominator == 1) return capacity;
        if (capacity != 0 && numerator > type(uint).max / capacity) revert ValueOverflow();
        unchecked {
            return (capacity * numerator) / denominator;
        }
    }

    /// @dev Initialize the input source without allocating output.
    function inputSource(Execution memory exec, uint budget, bytes calldata input) private pure returns (uint cur) {
        cur = Cursors.wrap(input);
        exec.budget = budget;
        exec.input = cur;
    }

    /// @dev Decode and initialize a bounded context without allocating output.
    function contextSource(
        Execution memory exec,
        uint budget,
        bytes calldata context
    ) private pure returns (uint input, uint state) {
        bytes32 account;
        // A genuine bounded calldata slice plus uint32 nested lengths cannot
        // overflow uint256 offsets. The tail check rejects subtraction underflow;
        // the final boundary check confines both lanes to the supplied slice.
        // Keep this local: unpackContext also accepts arbitrary absolute offsets.
        assembly ("memory-safe") {
            function fail(selector) {
                mstore(0, selector)
                revert(28, 4)
            }
            let start := context.offset
            let head := calldataload(start)
            if iszero(eq(shr(224, head), CONTEXT_KEY)) {
                fail(INVALID_BLOCK)
            }
            let limit := add(add(start, 8), and(shr(192, head), 0xffffffff))
            account := calldataload(add(start, 8))
            let stateHeader := add(start, 40)
            head := calldataload(stateHeader)
            if iszero(eq(shr(224, head), STATE_KEY)) {
                fail(INVALID_BLOCK)
            }
            let stateStart := add(stateHeader, 8)
            let stateEnd := add(stateStart, and(shr(192, head), 0xffffffff))
            let inputStart := add(stateEnd, 8)
            let inputLength := sub(limit, inputStart)
            // Match the INPUT tail check, including underflow and exact header length.
            if or(
                gt(inputLength, 0xffffffff),
                iszero(eq(shr(192, calldataload(stateEnd)), or(shl(32, INPUT_KEY), inputLength)))
            ) {
                fail(INVALID_BLOCK)
            }
            if iszero(eq(limit, add(start, context.length))) {
                fail(INVALID_BLOCK)
            }
            input := or(inputStart, shl(32, limit))
            state := or(stateStart, shl(32, stateEnd))
        }
        exec.account = account;
        exec.budget = budget;
        exec.input = input;
        exec.state = state;
    }

    /// @notice Open an execution containing only the current call-value budget.
    /// @dev Input/state cursors remain empty; initializes a growable output writer.
    /// @return exec Budget-only execution initialized with `msg.value`.
    function open() internal view returns (Execution memory exec) {
        exec.budget = msg.value;
        (exec.buffer, exec.output) = Encoder.init(0);
    }

    /// @notice Initialize an input-only execution and its native-value budget.
    /// @dev `exec` must be newly allocated or otherwise empty.
    /// @param exec Execution to initialize.
    /// @param descriptor Packed endpoint descriptor.
    /// @param budget Initial native-value budget.
    /// @param input Descriptor-backed input source.
    function openInput(Execution memory exec, uint descriptor, uint budget, bytes calldata input) internal pure {
        uint cur = inputSource(exec, budget, input);
        (exec.buffer, exec.output) = Encoder.init(outputCapacity(cur, 0, descriptor));
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
        uint cur = inputSource(exec, budget, input);
        (exec.buffer, exec.output) = Encoder.init(
            scaledCapacity(outputCapacity(cur, 0, descriptor), numerator, denominator)
        );
    }

    /// @notice Decode exactly one context and initialize a complete command execution.
    /// @dev `exec` must be newly allocated or otherwise empty. Initializes both
    /// source cursors independently. Rejects trailing context bytes.
    /// @param exec Execution to initialize.
    /// @param descriptor Packed command descriptor.
    /// @param budget Initial native-value budget.
    /// @param context Exactly one CONTEXT block carrying account, state, and input.
    function openContext(Execution memory exec, uint descriptor, uint budget, bytes calldata context) internal pure {
        (uint input, uint state) = contextSource(exec, budget, context);
        (exec.buffer, exec.output) = Encoder.init(outputCapacity(input, state, descriptor));
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
        (uint input, uint state) = contextSource(exec, budget, context);
        (exec.buffer, exec.output) = Encoder.init(
            scaledCapacity(outputCapacity(input, state, descriptor), numerator, denominator)
        );
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
    function exhaustInput(Execution memory exec) private pure {
        exec.input = Cursors.exhaust(exec.input);
    }

    // Block selection: enter, take, unpack. Selection consumes the parent in input.

    /// @notice Consume one block, validate a fixed prefix, and select its remaining payload.
    /// @dev Blocks validates the block and prefix once. Input advances past the parent.
    /// @return abs Original payload address; amount bytes are safe to read.
    /// @return payloadCur Clean cursor over the payload after the prefix.
    function enter(Execution memory exec, uint spec, uint amount) internal pure returns (uint abs, uint payloadCur) {
        (abs, payloadCur, exec.input) = exec.input.enter(spec, amount);
    }

    /// @notice Consume one block, validate a fixed prefix, and select its remaining payload.
    /// @dev Blocks validates the block and prefix once. Input advances past the parent.
    /// @return abs Original payload address; amount bytes are safe to read.
    /// @return payloadCur Clean cursor over the payload after the prefix.
    function enter(Execution memory exec, bytes4 key, uint amount) internal pure returns (uint abs, uint payloadCur) {
        (abs, payloadCur, exec.input) = exec.input.enter(key, amount);
    }

    /// @notice Consume one block, validate a fixed prefix, and select its remaining payload.
    /// @dev Blocks validates the block and prefix once. Input advances past the parent.
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
    function take(Execution memory exec) internal pure returns (uint blockCur) {
        (blockCur, exec.input) = exec.input.take();
    }

    /// @notice Consume one input block and return its complete encoding as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    function take(Execution memory exec, uint spec) internal pure returns (uint blockCur) {
        (blockCur, exec.input) = exec.input.take(spec);
    }

    /// @notice Consume one input block and return its complete encoding as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    function take(Execution memory exec, bytes4 key) internal pure returns (uint blockCur) {
        (blockCur, exec.input) = exec.input.take(key);
    }

    /// @notice Consume one input block and return its complete encoding as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    function takeFixed(Execution memory exec, uint header) internal pure returns (uint blockCur) {
        (blockCur, exec.input) = exec.input.takeFixed(header);
    }

    /// @notice Consume the entire input as one matching block and return its complete encoding as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    function takeExact(Execution memory exec, uint spec) internal pure returns (uint blockCur) {
        blockCur = exec.input.takeExact(spec);
        exhaustInput(exec);
    }

    /// @notice Consume the entire input as one exact-header block and return its complete encoding.
    /// @dev Delegates validation to Blocks; returns a clean child and preserves input metadata.
    function takeFixedExact(Execution memory exec, uint header) internal pure returns (uint blockCur) {
        blockCur = exec.input.takeFixedExact(header);
        exhaustInput(exec);
    }

    /// @notice Validate and consume all remaining input blocks with key.
    /// @dev Empty streams pass. Validates the requested key regardless of descriptor
    /// declarations; close still rejects any source bytes left unread.
    function takeInput(Execution memory exec, bytes4 key) internal pure returns (uint inputCur) {
        inputCur = exec.input;
        inputCur.expectRun(key);
        exec.input = Cursors.exhaust(inputCur);
    }

    /// @notice Validate and consume all remaining input blocks with an exact header.
    /// @dev Shares takeInput's empty-stream behavior; descriptor declarations do not affect validation.
    function takeInputFixed(Execution memory exec, uint header) internal pure returns (uint inputCur) {
        inputCur = exec.input;
        inputCur.expectRunFixed(header);
        exec.input = Cursors.exhaust(inputCur);
    }

    /// @notice Validate and consume the remaining input as ANNOTATION blocks.
    /// @dev Empty streams pass. Checks every parent and its exact final BYTES child;
    /// annotation payloads remain opaque. Returns the original stream cursor.
    /// Descriptor declarations do not affect validation; state remains unconsumed.
    function takeAnnotations(Execution memory exec) internal pure returns (uint inputCur) {
        inputCur = exec.input;
        uint cur = inputCur;
        while (Cursors.more(cur)) {
            (, , cur) = cur.unpackAnnotation();
        }
        exec.input = cur;
    }

    /// @notice Validate and consume all remaining state blocks with key.
    /// @dev Empty streams pass. Validates the requested key regardless of descriptor
    /// declarations; close still rejects any source bytes left unread.
    function takeState(Execution memory exec, bytes4 key) internal pure returns (uint stateCur) {
        stateCur = exec.state;
        stateCur.expectRun(key);
        exec.state = Cursors.exhaust(stateCur);
    }

    /// @notice Validate and consume all remaining state blocks with an exact header.
    /// @dev Shares takeState's empty-stream behavior; descriptor declarations do not affect validation.
    function takeStateFixed(Execution memory exec, uint header) internal pure returns (uint stateCur) {
        stateCur = exec.state;
        stateCur.expectRunFixed(header);
        exec.state = Cursors.exhaust(stateCur);
    }

    /// @notice Validate and consume the remaining state as BALANCE blocks.
    /// @dev Returns a clean stream cursor; shares takeStateFixed's lane behavior.
    function takeBalances(Execution memory exec) internal pure returns (uint stateCur) {
        return takeStateFixed(exec, Headers.Balance);
    }

    /// @notice Consume one input block and return its payload as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    function unpack(Execution memory exec, uint spec) internal pure returns (uint payloadCur) {
        (payloadCur, exec.input) = exec.input.unpack(spec);
    }

    /// @notice Consume one input block and return its payload as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    function unpack(Execution memory exec, bytes4 key) internal pure returns (uint payloadCur) {
        (payloadCur, exec.input) = exec.input.unpack(key);
    }

    /// @notice Consume one input block and return its payload as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    function unpackFixed(Execution memory exec, uint header) internal pure returns (uint payloadCur) {
        (payloadCur, exec.input) = exec.input.unpackFixed(header);
    }

    /// @notice Consume the entire input as one matching block and return its payload as a cursor.
    /// @dev Delegates validation to Blocks; the returned range has no metadata.
    function unpackExact(Execution memory exec, uint spec) internal pure returns (uint payloadCur) {
        payloadCur = exec.input.unpackExact(spec);
        exhaustInput(exec);
    }

    /// @notice Consume the entire input as one exact-header block and return its payload.
    /// @dev Delegates validation to Blocks; returns a clean child and preserves input metadata.
    function unpackFixedExact(Execution memory exec, uint header) internal pure returns (uint payloadCur) {
        payloadCur = exec.input.unpackFixedExact(header);
        exhaustInput(exec);
    }

    /// @notice Consume a LIST and return its clean payload cursor.
    function unpackList(Execution memory exec) internal pure returns (uint itemsCur) {
        (itemsCur, exec.input) = exec.input.unpackList();
    }

    /// @notice Consume a custom list and return its clean payload cursor.
    function unpackList(Execution memory exec, uint spec) internal pure returns (uint itemsCur) {
        return unpack(exec, spec);
    }

    // Raw input navigation.

    /// @notice Advance input by a raw byte count and return its previous absolute position.
    /// @dev Validates containment once; no block header or schema is inspected.
    function advance(Execution memory exec, uint amount) internal pure returns (uint abs) {
        (abs, exec.input) = Cursors.enter(exec.input, amount);
    }

    // -------------------------------------------------------------------------
    // Expectations
    // -------------------------------------------------------------------------

    /// @notice Consume one LIMITS input and check final quantities directly against calldata.
    /// @param exec Execution whose input cursor is bounded and advanced by one block.
    /// @param amount Final asset amount, checked against the inclusive minimum.
    /// @param debt Final debt, checked against the literal inclusive maximum.
    function expectLimits(Execution memory exec, uint amount, uint debt) internal pure {
        exec.input = exec.input.expectLimits(amount, debt);
    }

    /// @notice Consume one BALANCE_CONSTRAINTS input and check an asset and amount directly against calldata.
    /// @dev Validates the header and containment once before asset and quantity checks.
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

    /// @notice Consume one CODES input block and return its packed identifiers.
    /// @dev Validates block shape and containment, not code semantics.
    function unpackCodes(Execution memory exec) internal pure returns (uint codes) {
        (codes, exec.input) = exec.input.unpackCodes();
    }

    /// @notice Decode and consume one LIMITS block.
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
    function unpackBalanceConstraints(Execution memory exec) internal pure returns (BalanceConstraints memory value) {
        (value, exec.input) = exec.input.unpackBalanceConstraints();
    }

    /// @notice Decode and consume one QUOTE input with full-width asset and liability quantities.
    function unpackQuote(
        Execution memory exec
    ) internal pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt) {
        (asset, amount, liability, debt, exec.input) = exec.input.unpackQuote();
    }

    /// @notice Decode one QUOTE into its structured value.
    function unpackQuoteValue(Execution memory exec) internal pure returns (Quote memory quote) {
        (quote.asset, quote.amount, quote.liability, quote.debt) = unpackQuote(exec);
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
        (from, to, asset, amount, exec.input) = exec.input.unpackTransaction();
    }

    /// @notice Decode one TRANSACTION block into its structured value.
    /// @param exec Execution whose input cursor is advanced.
    /// @return value Decoded transaction.
    function unpackTransactionValue(Execution memory exec) internal pure returns (Tx memory value) {
        (value.from, value.to, value.asset, value.amount) = unpackTransaction(exec);
    }

    /// @notice Decode POSITION_CONSTRAINTS with exact denominations and inclusive full-width bounds.
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
    function unpackBooking(Execution memory exec) internal pure returns (Booking memory value) {
        (value, exec.input) = exec.input.unpackBooking();
    }

    // -------------------------------------------------------------------------
    // Dynamic block decoding
    // -------------------------------------------------------------------------

    /// @notice Decode BYTES and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackBytes(Execution memory exec) internal pure returns (uint payloadCur) {
        (payloadCur, exec.input) = exec.input.unpackBytes();
    }

    /// @notice Decode STRING and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackString(Execution memory exec) internal pure returns (uint textCur) {
        (textCur, exec.input) = exec.input.unpackString();
    }

    /// @notice Decode RELAY and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackRelay(Execution memory exec) internal pure returns (uint inputCur, uint stepsCur) {
        (inputCur, stepsCur, exec.input) = exec.input.unpackRelay();
    }

    /// @notice Decode ANNOTATION and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackAnnotation(Execution memory exec) internal pure returns (uint entity, uint dataCur) {
        (entity, dataCur, exec.input) = exec.input.unpackAnnotation();
    }

    /// @notice Decode LABEL and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackLabel(Execution memory exec) internal pure returns (bytes32 namespace, uint nameCur) {
        (namespace, nameCur, exec.input) = exec.input.unpackLabel();
    }

    /// @notice Decode SCHEMA and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackSchema(Execution memory exec) internal pure returns (uint spec, uint bodyCur) {
        (spec, bodyCur, exec.input) = exec.input.unpackSchema();
    }

    /// @notice Decode CONTEXT and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackContext(
        Execution memory exec
    ) internal pure returns (bytes32 account, uint stateCur, uint inputCur) {
        (account, stateCur, inputCur, exec.input) = exec.input.unpackContext();
    }

    /// @notice Decode STEP and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackStep(Execution memory exec) internal pure returns (uint cmd, uint value, uint inputCur) {
        (cmd, value, inputCur, exec.input) = exec.input.unpackStep();
    }

    /// @notice Consume SWAP input and return its fixed fields and LIST payload cursor.
    /// @dev Validates structural encoding; the caller validates hop blocks and route semantics.
    function unpackSwap(Execution memory exec) internal pure returns (bytes32 asset, uint amount, uint hopsCur) {
        (asset, amount, hopsCur, exec.input) = exec.input.unpackSwap();
    }

    /// @notice Decode CALL and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackCall(Execution memory exec) internal pure returns (uint target, uint value, uint payloadCur) {
        (target, value, payloadCur, exec.input) = exec.input.unpackCall();
    }

    /// @notice Decode DISPATCH and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
    function unpackDispatch(
        Execution memory exec
    ) internal pure returns (uint portal, uint resources, uint payloadCur) {
        (portal, resources, payloadCur, exec.input) = exec.input.unpackDispatch();
    }

    /// @notice Decode RECOVER and retain dynamic payloads as calldata cursors.
    /// @dev Blocks validates and advances input once; returned payload cursors
    /// exclude child headers and have no metadata. Convert only when bytes/text are needed.
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

    /// @notice Append a STATUS block to execution output.
    /// @param exec Execution receiving the block.
    /// @param code Status code to encode.
    function outputStatus(Execution memory exec, uint code) internal pure {
        (exec.buffer, exec.output) = exec.output.writeStatus(exec.buffer, code);
    }

    /// @notice Append one CODES block containing packed identifiers.
    /// @dev Delegates allocation and writing to Encoder; callers define code semantics.
    function outputCodes(Execution memory exec, uint codes) internal pure {
        (exec.buffer, exec.output) = exec.output.writeCodes(exec.buffer, codes);
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
    /// @param limits Packed inclusive minimum (high 128 bits) and maximum (low 128 bits); meaning is context-dependent.
    function outputLimits(Execution memory exec, uint limits) internal pure {
        (exec.buffer, exec.output) = exec.output.writeLimits(exec.buffer, limits);
    }

    /// @notice Append a QUOTE with full-width asset and liability quantities.
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
    function outputQuote(Execution memory exec, Quote memory quote) internal pure {
        outputQuote(exec, quote.asset, quote.amount, quote.liability, quote.debt);
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
    function outputPosition(Execution memory exec, Position memory value) internal pure {
        Encoder.writePositionAt(reserve(exec, Sizes.Position), value);
    }

    /// @notice Append one structured BOOKING output block.
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
        (exec.buffer, exec.output) = exec.output.writeTransaction(exec.buffer, from, to, asset, amount);
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
    function outputSwap(Execution memory exec, bytes32 asset, uint amount, bytes memory hops) internal pure {
        (exec.buffer, exec.output) = exec.output.writeSwapWrap(exec.buffer, asset, amount, hops);
    }

    /// @notice Append SWAP output from a complete validated LIST child cursor.
    function outputSwap(Execution memory exec, bytes32 asset, uint amount, uint hopsCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeSwap(exec.buffer, asset, amount, hopsCur);
    }

    /// @notice Append SWAP output by wrapping a validated ASSET stream cursor in LIST.
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

    /// @notice Append a LABEL block to execution output.
    /// @param exec Execution receiving the block.
    /// @param namespace Label namespace to encode.
    /// @param name Label text to encode.
    function outputLabel(Execution memory exec, bytes32 namespace, string memory name) internal pure {
        (exec.buffer, exec.output) = exec.output.writeLabelWrap(exec.buffer, namespace, bytes(name));
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
    function outputBlock(Execution memory exec, uint dataCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBlock(exec.buffer, dataCur);
    }

    /// @notice Append LIST output using a complete validated block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    function outputList(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBlock(exec.buffer, valueCur);
    }

    /// @notice Append BYTES output using a complete validated block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    function outputBytes(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBlock(exec.buffer, valueCur);
    }

    /// @notice Append STRING output using a complete validated block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    function outputString(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBlock(exec.buffer, valueCur);
    }

    /// @notice Append STEP output using a complete validated INPUT child block.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    function outputStep(Execution memory exec, uint cmd, uint value, uint inputCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeStep(exec.buffer, cmd, value, inputCur);
    }

    /// @notice Append CALL output using complete validated BYTES child blocks.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    function outputCall(Execution memory exec, uint target, uint value, uint payloadCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeCall(exec.buffer, target, value, payloadCur);
    }

    /// @notice Append DISPATCH output using complete validated BYTES child blocks.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    function outputDispatch(Execution memory exec, uint portal, uint resources, uint payloadCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeDispatch(exec.buffer, portal, resources, payloadCur);
    }

    /// @notice Append RELAY output using complete validated INPUT and BYTES child blocks.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    function outputRelay(Execution memory exec, uint inputCur, uint stepsCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeRelay(exec.buffer, inputCur, stepsCur);
    }

    /// @notice Append CONTEXT output using complete validated STATE and INPUT child blocks.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    function outputContext(Execution memory exec, bytes32 account, uint stateCur, uint inputCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeContext(exec.buffer, account, stateCur, inputCur);
    }

    /// @notice Append RECOVER output using complete validated BYTES child blocks.
    /// @dev Cursor ranges include headers and must have the required schema. No revalidation or source advancement.
    function outputRecover(
        Execution memory exec,
        uint handler,
        uint value,
        bytes32 recoverykey,
        uint witnessCur
    ) internal pure {
        (exec.buffer, exec.output) = exec.output.writeRecover(exec.buffer, handler, value, recoverykey, witnessCur);
    }

    /// @notice Append LABEL from a complete validated STRING block cursor.
    /// @dev Source is not advanced or revalidated; its range must belong to calldata.
    function outputLabel(Execution memory exec, bytes32 namespace, uint nameCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeLabel(exec.buffer, namespace, nameCur);
    }

    /// @notice Append SCHEMA from a complete validated STRING block cursor.
    /// @dev Source is not advanced or revalidated; its range must belong to calldata.
    function outputSchema(Execution memory exec, uint spec, uint bodyCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeSchema(exec.buffer, spec, bodyCur);
    }

    /// @notice Append a custom block to execution output by wrapping a validated calldata payload cursor.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    function outputBlockWrap(Execution memory exec, uint spec, uint dataCur) internal pure {
        Specs.validate(spec, Encoder.length(dataCur));
        (exec.buffer, exec.output) = exec.output.writeBlock(exec.buffer, Specs.key(spec), dataCur);
    }

    /// @notice Append a LIST block to execution output by wrapping a validated calldata payload cursor.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    function outputListWrap(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeList(exec.buffer, valueCur);
    }

    /// @notice Append a BYTES block to execution output by wrapping a validated calldata payload cursor.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    function outputBytesWrap(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeBytes(exec.buffer, valueCur);
    }

    /// @notice Append a STRING block to execution output by wrapping a validated calldata payload cursor.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    function outputStringWrap(Execution memory exec, uint valueCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeString(exec.buffer, valueCur);
    }

    /// @notice Append a STEP block to execution output by wrapping a validated input payload cursor in INPUT.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    function outputStepWrap(Execution memory exec, uint cmd, uint value, uint inputCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeStepWrap(exec.buffer, cmd, value, inputCur);
    }

    /// @notice Append a CALL block to execution output by wrapping a validated payload cursor in BYTES.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    function outputCallWrap(Execution memory exec, uint target, uint value, uint payloadCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeCallWrap(exec.buffer, target, value, payloadCur);
    }

    /// @notice Append a DISPATCH block to execution output by wrapping a validated payload cursor in BYTES.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    function outputDispatchWrap(Execution memory exec, uint portal, uint resources, uint payloadCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeDispatchWrap(exec.buffer, portal, resources, payloadCur);
    }

    /// @notice Append a RELAY block to execution output by wrapping validated payload cursors in INPUT and BYTES.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    function outputRelayWrap(Execution memory exec, uint inputCur, uint stepsCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeRelayWrap(exec.buffer, inputCur, stepsCur);
    }

    /// @notice Append a CONTEXT block to execution output by wrapping validated payload cursors in STATE and INPUT.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    function outputContextWrap(Execution memory exec, bytes32 account, uint stateCur, uint inputCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeContextWrap(exec.buffer, account, stateCur, inputCur);
    }

    /// @notice Append a RECOVER block to execution output by wrapping a validated witness payload cursor in BYTES.
    /// @dev Sources exclude headers and must be valid calldata ranges; they are not advanced or revalidated.
    function outputRecoverWrap(
        Execution memory exec,
        uint handler,
        uint value,
        bytes32 recoverykey,
        uint witnessCur
    ) internal pure {
        (exec.buffer, exec.output) = exec.output.writeRecoverWrap(exec.buffer, handler, value, recoverykey, witnessCur);
    }

    /// @notice Append LABEL from a payload cursor; adds the STRING header.
    /// @dev Source is not advanced or revalidated; its range must belong to calldata.
    function outputLabelWrap(Execution memory exec, bytes32 namespace, uint nameCur) internal pure {
        (exec.buffer, exec.output) = exec.output.writeLabelWrap(exec.buffer, namespace, nameCur);
    }

    /// @notice Append SCHEMA from a payload cursor; adds the STRING header.
    /// @dev Source is not advanced or revalidated; its range must belong to calldata.
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
    function expectEnd(Execution memory exec) internal pure {
        Cursors.expectEnd(exec.input);
        Cursors.expectEnd(exec.state);
    }

    /// @notice Finalize output without checking sources or changing the budget.
    /// @dev Ends the writer lifecycle. Caller must establish source consumption
    /// through a complete loop over valid cursors, expectEnd, or close.
    function finish(Execution memory exec) internal pure returns (bytes memory out) {
        if (exec.buffer.length == 0) return Encoder.allocate(0);
        out = exec.output.finish(exec.buffer);
    }

    /// @notice Finalize and conditionally log an OUTPUT container for an endpoint.
    /// @dev Same lifecycle as finish. Descriptor logging selection comes from lane
    /// codes; id is the matching registered endpoint ID. Returned bytes are unwrapped.
    function finish(Execution memory exec, uint id, uint descriptor) internal returns (bytes memory out) {
        out = finish(exec);
        if (descriptor & LogOutput != 0) Logs.memWrap(id, Keys.Output, out);
    }

    /// @notice Check consumption, finalize output, and return and clear the budget.
    function close(Execution memory exec) internal pure returns (bytes memory output, uint credit) {
        expectEnd(exec);
        output = finish(exec);
        credit = drainBudget(exec);
    }

    /// @notice Checked close with descriptor-selected output logging.
    function close(
        Execution memory exec,
        uint id,
        uint descriptor
    ) internal returns (bytes memory output, uint credit) {
        expectEnd(exec);
        output = finish(exec, id, descriptor);
        credit = drainBudget(exec);
    }
}
