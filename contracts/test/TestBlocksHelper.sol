// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {Encoder} from "../codec/Encoder.sol";
import {UnexpectedValue, UnexpectedPosition, InvalidBlock} from "../utils/Errors.sol";
import {Blocks} from "../codec/Blocks.sol";

import {LegacyBuffers} from "./LegacyBuffers.sol";
import {Sizes, Specs} from "../codec/Specs.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Flags} from "../utils/Flags.sol";
import {Budget, Budgets} from "../core/Budget.sol";
import {CounterpartyAnnot} from "../annotations/Counterparty.sol";

using Budgets for Budget;
using Executions for Execution;

contract TestBlocksHelper is CounterpartyAnnot {
    bytes4 private constant TestKey = bytes4(uint32(1));

    function openInput(
        bytes calldata input,
        uint descriptor
    ) private view returns (Execution memory exec) {
        exec.openInput(descriptor, msg.value, input);
    }

    function openExecution(
        bytes calldata context,
        uint descriptor
    ) private view returns (Execution memory exec) {
        exec.openContext(descriptor, msg.value, context);
    }

    function transactionSpec() external pure returns (bytes32) {
        return bytes32(Specs.Transaction);
    }

    function specRanges() external pure returns (uint32 fixedMin, uint32 fixedMax, uint32 dynamicMin, uint32 dynamicMax) {
        (, fixedMin, fixedMax) = Specs.decode(Specs.Transaction);
        (, dynamicMin, dynamicMax) = Specs.decode(Specs.Step);
    }

    function specHint(uint32 hint) external pure returns (uint24) {
        uint capacity = Specs.allocation(Specs.create(TestKey, 0, 0, hint), 1);
        return uint24(capacity - Sizes.Header);
    }

    function exactSpec(uint32 key, uint32 size) external pure returns (uint) {
        return Specs.create(key, size);
    }


    function publishCounterparty(uint entity, bytes32 account) external {
        annotateCounterparty(entity, account);
    }

    function blockCapacity() external pure returns (uint) {
        return Specs.allocation(Specs.Balance, 6);
    }

    function describeSpecs(uint state, uint input, uint output) external pure returns (uint) {
        return Executions.describe(state, input, output);
    }

    function descriptorWord() external pure returns (uint) {
        return Executions.describe(
            Specs.Balance,
            Specs.Asset,
            Specs.AssetAmount);
    }

    function descriptorOpens(
        bytes calldata context,
        bytes calldata input
    ) external pure returns (uint stateCursor, uint stateWriter, uint inputCursor, uint inputWriter) {
        uint descriptor = Executions.describe(
            Specs.Balance,
            Specs.Asset,
            Specs.AssetAmount);
        Execution memory stateExec;
        Execution memory inputExec;
        stateExec.openContext(descriptor, 0, context);
        inputExec.openInput(descriptor, 0, input);
        (stateCursor, stateWriter) = (stateExec.state, stateExec.output);
        (inputCursor, inputWriter) = (inputExec.input, inputExec.output);
    }

    function executionWriterHint(
        bytes calldata context,
        uint stateSpec,
        uint inputSpec,
        uint outputSpec
    ) external view returns (uint len) {
        uint descriptor = Executions.describe(stateSpec, inputSpec, outputSpec);
        Execution memory exec = openExecution(context, descriptor);
        len = Cursors.limit(exec.output);
    }

    function executionOutputPosition(
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) external view returns (bytes memory output) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.Empty, Specs.Position);
        Execution memory exec = openInput(msg.data[0:0], descriptor);
        Executions.outputPosition(exec, asset, amount, liability, debt, bytes32(0));
        output = Executions.finish(exec);
    }

    function executionOutputHostAsset(uint host, bytes32 asset) external view returns (bytes memory output) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.Empty, Specs.HostAsset);
        Execution memory exec = openInput(msg.data[0:0], descriptor);
        Executions.outputHostAsset(exec, host, asset);
        output = Executions.finish(exec);
    }

    function executionUnpackPosition(
        bytes calldata context
    ) external view returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        uint descriptor = Executions.describe(Specs.Position, Specs.Empty, Specs.Empty);
        Execution memory exec = openExecution(context, descriptor);
        return exec.unpackPosition();
    }

    function executionEnterAssetAmount(
        bytes calldata context
    ) external view returns (bytes32 stateAsset, uint stateAmount, bytes32 inputAsset, uint inputAmount) {
        uint descriptor = Executions.describe(Specs.Balance, Specs.List, Specs.Empty);
        Execution memory exec = openExecution(context, descriptor);
        uint payloadCur = exec.unpackList();
        uint end = uint32(payloadCur >> 32);
        // This harness explicitly scopes its remaining reads to the selected payload.
        exec.input = payloadCur;
        (stateAsset, stateAmount) = exec.unpackBalance();
        (inputAsset, inputAmount) = exec.unpackAssetAmount();
        if (uint32(exec.input) != end) revert UnexpectedPosition();
    }

    /// @notice Gas baseline reproducing the removed tagged, relative two-lane cursor path.
    /// @dev Kept to compare traversal correctness and detect material gas regressions.
    function legacyExecutionEnterAssetAmount(
        bytes calldata context
    ) external pure returns (bytes32 stateAsset, uint stateAmount, bytes32 inputAsset, uint inputAmount) {
        uint abs;
        assembly ("memory-safe") { abs := context.offset }
        (, bytes calldata state, bytes calldata input, uint endContext) = LegacyBlocks.unpackContext(abs);
        if (endContext != abs + context.length) revert InvalidBlock();
        return legacyEnterAssetAmount(state, input);
    }

    function legacyEnterAssetAmount(bytes calldata state, bytes calldata input)
        private pure returns (bytes32 stateAsset, uint stateAmount, bytes32 inputAsset, uint inputAmount)
    {
        // Reproduce the legacy descriptor bytes used by this baseline.
        uint descriptor = (uint(uint32(Specs.key(Specs.Balance))) << 224) | (uint(1) << 216)
            | (uint(uint32(Specs.key(Specs.List))) << 184) | (uint(1) << 176);
        uint inputCursor;
        uint stateCursor;
        assembly ("memory-safe") {
            inputCursor := or(
                or(or(shl(32, input.offset), shl(64, input.length)), shl(96, byte(9, descriptor))),
                shl(120, 1)
            )
            stateCursor := or(
                or(or(shl(32, state.offset), shl(64, state.length)), shl(96, byte(4, descriptor))),
                shl(120, 2)
            )
        }
        uint decoders = inputCursor | (stateCursor << 128);

        uint inputAbs = legacyAbsolute(decoders);
        uint next;
        uint end;
        (, next, end) = LegacyBlocks.enter(inputAbs, Specs.List, 0);
        decoders = legacySeekAbs(decoders, next);

        decoders = legacySelect(decoders, 2);
        uint stateAbs;
        (decoders, stateAbs) = legacyConsume(decoders, Sizes.Balance);
        (stateAsset, stateAmount) = LegacyBlocks.unpackBalance(stateAbs);

        decoders = legacySelect(decoders, 1);
        (decoders, inputAbs) = legacyConsume(decoders, Sizes.AssetAmount);
        (inputAsset, inputAmount) = LegacyBlocks.unpackAssetAmount(inputAbs);
        if (legacyAbsolute(decoders) != end) revert();
    }

    function legacyAbsolute(uint cur) private pure returns (uint) {
        return uint32(cur) + uint32(cur >> 32);
    }

    function legacySeekAbs(uint cur, uint abs) private pure returns (uint updated) {
        uint offset = uint32(cur >> 32);
        if (abs < offset) revert();
        uint i = abs - offset;
        if (i < uint32(cur) || i > uint32(cur >> 64)) revert();
        updated = (cur & ~uint(type(uint32).max)) | i;
    }

    function legacySelect(uint cur, uint8 tag) private pure returns (uint updated) {
        if (uint8(cur >> 120) == tag) return cur;
        updated = (cur << 128) | (cur >> 128);
        if (uint8(updated >> 120) != tag) revert();
    }

    function legacyConsume(uint cur, uint amount) private pure returns (uint updated, uint abs) {
        uint i = uint32(cur);
        uint len = uint32(cur >> 64);
        if (amount > len - i) revert();
        abs = uint32(cur >> 32) + i;
        updated = cur + amount;
    }

    function executionList(bytes calldata input, uint spec) external view returns (uint itemsLen, bool complete) {
        uint descriptor = Executions.describe(Specs.Empty, spec, Specs.Empty);
        Execution memory exec = openInput(input, descriptor);
        uint itemsCur = exec.unpackList(spec);
        itemsLen = Cursors.limit(itemsCur) - Cursors.position(itemsCur);
        complete = !Executions.more(exec);
    }

    function executionTakeBlock(
        bytes calldata context,
        bytes4 inputKey,
        bytes4 expectedKey
    ) external view returns (bytes calldata data, bytes32 asset, uint amount, bool complete) {
        uint inputSpec = Specs.create(inputKey, 0, 0, 0);
        uint descriptor = Executions.describe(Specs.Balance, inputSpec, Specs.Empty);
        Execution memory exec = openExecution(context, descriptor);
        data = Blocks.toBytes(exec.take(expectedKey));
        (asset, amount) = exec.unpackBalance();
        complete = !Executions.more(exec);
    }

    function executionRaw(
        bytes calldata context
    ) external view returns (bytes calldata beforeState, bytes calldata afterState, bytes calldata rawInput) {
        uint descriptor = Executions.describe(Specs.Balance, Specs.AssetAmount, Specs.Empty);
        Execution memory exec = openExecution(context, descriptor);
        beforeState = Blocks.toBytesChecked(exec.state);
        exec.unpackBalance();
        afterState = Blocks.toBytesChecked(exec.state);
        rawInput = Blocks.toBytesChecked(exec.input);
    }

    function executionRawEmptyState(
        bytes calldata input
    ) external view returns (bytes calldata state) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.AssetAmount, Specs.Empty);
        Execution memory exec = openInput(input, descriptor);
        return Blocks.toBytesChecked(exec.state);
    }

    function executionTakeState(
        bytes calldata context
    ) external view returns (bytes calldata data, bool complete) {
        uint descriptor = Executions.describe(Specs.Balance, Specs.Empty, Specs.Empty);
        Execution memory exec = openExecution(context, descriptor);
        data = Blocks.toBytesChecked(Executions.takeState(exec, Specs.key(Specs.Balance)));
        complete = !Executions.more(exec);
    }

    function executionTakeInput(
        bytes calldata input
    ) external view returns (bytes calldata data, bool complete) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.AssetAmount, Specs.Empty);
        Execution memory exec = openInput(input, descriptor);
        data = Blocks.toBytesChecked(Executions.takeInput(exec, Specs.key(Specs.AssetAmount)));
        complete = !Executions.more(exec);
    }

    function executionForwardStreams(bytes calldata context, uint stateSpec, uint inputSpec)
        external view returns (bytes memory)
    {
        Execution memory exec = openExecution(context, Executions.describe(stateSpec, inputSpec, Specs.Empty));
        Executions.takeState(exec, Specs.key(Specs.Balance));
        Executions.takeInput(exec, Specs.key(Specs.AssetAmount));
        return exec.finish();
    }

    function executionFinishUnread(bytes calldata input) external view returns (bytes memory) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.AssetAmount, Specs.Empty);
        Execution memory exec = openInput(input, descriptor);
        Executions.expectEnd(exec);
        return Executions.finish(exec);
    }

    function executionFinishUnreadState(bytes calldata context) external view returns (bytes memory) {
        uint descriptor = Executions.describe(Specs.Balance, Specs.Empty, Specs.Empty);
        Execution memory exec = openExecution(context, descriptor);
        Executions.expectEnd(exec);
        return Executions.finish(exec);
    }

    function executionEnterWords(bytes calldata input) external view returns (bytes32 first, bytes32 second) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.List, Specs.Empty);
        Execution memory exec = openInput(input, descriptor);
        (uint abs, uint payloadCur) = exec.enter(Specs.List, 64);
        unchecked {
            first = Blocks.read32(abs);
            second = Blocks.read32(abs + 32);
        }
        if (uint32(payloadCur) != uint32(payloadCur >> 32)) revert UnexpectedPosition();
    }

    function executionEnterKeyAdvance(
        bytes calldata input,
        bytes4 key,
        uint amount
    ) external view returns (uint body, uint i, uint end) {
        uint offset;
        assembly ("memory-safe") {
            offset := input.offset
        }

        uint descriptor = Executions.describe(Specs.Empty, Specs.List, Specs.Empty);
        Execution memory exec = openInput(input, descriptor);
        uint payloadCur;
        (body, payloadCur) = exec.enter(key, amount);
        end = uint32(payloadCur >> 32);
        i = uint32(payloadCur);
        return (body - offset, i - offset, end - offset);
    }

    function executionAdvance(
        bytes calldata input,
        uint amount
    ) external view returns (uint abs, bytes32 value, bool complete) {
        uint offset;
        assembly ("memory-safe") {
            offset := input.offset
        }

        uint descriptor = Executions.describe(Specs.Empty, Specs.List, Specs.Empty);
        Execution memory exec = openInput(input, descriptor);
        uint payloadCur = exec.unpackList();
        uint end = uint32(payloadCur >> 32);
        // This harness explicitly scopes its remaining reads to the selected payload.
        exec.input = payloadCur;
        abs = uint32(exec.input);
        exec.advance(amount);
        value = LegacyBlocks.read32(abs);
        complete = amount == end - abs;
        return (abs - offset, value, complete);
    }

    function executionTake(
        bytes calldata input,
        uint amount
    ) external view returns (uint abs, bytes32 value, bool complete) {
        uint offset;
        assembly ("memory-safe") {
            offset := input.offset
        }

        uint descriptor = Executions.describe(Specs.Empty, Specs.List, Specs.Empty);
        Execution memory exec = openInput(input, descriptor);
        uint payloadCur = exec.unpackList();
        uint end = uint32(payloadCur >> 32);
        // This harness explicitly scopes its remaining reads to the selected payload.
        exec.input = payloadCur;
        abs = exec.advance(amount);
        value = LegacyBlocks.read32(abs);
        complete = amount == end - abs;
        return (abs - offset, value, complete);
    }

    function executionEnterSized(bytes calldata input)
        external
        view
        returns (bytes1 a, bytes2 b, bytes4 c, bytes8 d, bytes16 e, bytes32 f)
    {
        uint descriptor = Executions.describe(Specs.Empty, Specs.List, Specs.Empty);
        Execution memory exec = openInput(input, descriptor);
        (uint abs, uint payloadCur) = exec.enter(Specs.List, 63);
        unchecked {
            a = Blocks.read1(abs);
            b = Blocks.read2(abs + 1);
            c = Blocks.read4(abs + 3);
            d = Blocks.read8(abs + 7);
            e = Blocks.read16(abs + 15);
            f = Blocks.read32(abs + 31);
        }
        if (uint32(payloadCur) != uint32(payloadCur >> 32)) revert UnexpectedPosition();
    }

    function writerCopies(bytes calldata value) external pure returns (bytes memory) {
        (bytes memory buffer, uint writer) = Encoder.init(0);
        uint cur = Cursors.wrap(value);
        (buffer, writer) = Encoder.writeBlock(writer, buffer, TestKey, cur);
        (buffer, writer) = Encoder.writeList(writer, buffer, cur);
        (buffer, writer) = Encoder.writeBytes(writer, buffer, cur);
        (buffer, writer) = Encoder.writeStepWrap(writer, buffer, 1, 2, cur);
        (buffer, writer) = Encoder.writeCallWrap(writer, buffer, 3, 4, cur);
        (buffer, writer) = Encoder.writeRelayWrap(writer, buffer, abi.encode(uint(5), uint(6)), value);
        (buffer, writer) = Encoder.writeDispatchWrap(writer, buffer, 7, 8, cur);
        (buffer, writer) = Encoder.writeContextWrap(writer, buffer, bytes32(uint(9)), cur, cur);
        (buffer, writer) = Encoder.writeRecoverWrap(writer, buffer, 10, 11, bytes32(uint(12)), cur);
        return Encoder.finish(writer, buffer);
    }

    function writerCopy(bytes calldata value) external pure returns (bytes memory) {
        (bytes memory buffer, uint writer) = Encoder.init(value.length + 2);
        uint abs;
        (buffer, abs, writer) = Encoder.reserve(writer, buffer, value.length + 2);
        assembly ("memory-safe") { mstore8(abs, 0xaa) }
        abs = Encoder.copy(abs + 1, Cursors.wrap(value));
        assembly ("memory-safe") { mstore8(abs, 0xbb) }
        return Encoder.finish(writer, buffer);
    }

    function stringCopies(
        string calldata value
    ) external view returns (bytes memory factory, bytes memory written, bytes memory output) {
        factory = LegacyBlocks.createStringCopy(value);

        (bytes memory writerBuffer, uint writer) = Encoder.init(Specs.allocation(Specs.String, 1));
        (writerBuffer, writer) = Encoder.writeString(writer, writerBuffer, Cursors.wrap(bytes(value)));
        written = Encoder.finish(writer, writerBuffer);

        uint descriptor = Executions.describe(Specs.Empty, Specs.Empty, Specs.String);
        Execution memory exec = openInput(msg.data[0:0], descriptor);
        Executions.outputStringWrap(exec, Cursors.wrap(bytes(value)));
        output = Executions.finish(exec);
    }

    function bufferCopy(
        uint capacity,
        uint offset,
        bytes calldata value
    ) external pure returns (bytes memory buffer, uint next) {
        buffer = new bytes(capacity);
        next = LegacyBuffers.copy(buffer, offset, value);
    }

    function factoryCopies(bytes calldata value) external pure returns (bytes memory) {
        bytes memory leaves = bytes.concat(
            LegacyBlocks.createCopy(TestKey, value),
            LegacyBlocks.createListCopy(value),
            LegacyBlocks.createBytesCopy(value)
        );
        bytes memory composites = bytes.concat(
            LegacyBlocks.createStepCopy(1, 2, value),
            LegacyBlocks.createCallCopy(3, 4, value),
            LegacyBlocks.createRelay(abi.encode(uint(5), uint(6)), value),
            LegacyBlocks.createDispatchCopy(7, 8, value)
        );
        return bytes.concat(
            leaves,
            composites,
            LegacyBlocks.createContextCopy(bytes32(uint(9)), value, value),
            LegacyBlocks.createRecoverCopy(10, 11, bytes32(uint(12)), value)
        );
    }

    function executionCopies(bytes calldata value) external view returns (bytes memory) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.Empty, Specs.Bytes);
        Execution memory exec = openInput(msg.data[0:0], descriptor);
        Executions.outputBlockWrap(exec, Specs.create(TestKey, 0, 0, 0), Cursors.wrap(value));
        Executions.outputListWrap(exec, Cursors.wrap(value));
        Executions.outputBytesWrap(exec, Cursors.wrap(value));
        Executions.outputStepWrap(exec, 1, 2, Cursors.wrap(value));
        Executions.outputCallWrap(exec, 3, 4, Cursors.wrap(value));
        Executions.outputRelay(exec, abi.encode(uint(5), uint(6)), value);
        Executions.outputDispatchWrap(exec, 7, 8, Cursors.wrap(value));
        Executions.outputContextWrap(exec, bytes32(uint(9)), Cursors.wrap(value), Cursors.wrap(value));
        Executions.outputRecoverWrap(exec, 10, 11, bytes32(uint(12)), Cursors.wrap(value));
        return Executions.finish(exec);
    }

    function lazyBalance(bytes32 asset, uint amount) external pure returns (bytes memory) {
        (bytes memory writerBuffer, uint writer) = Encoder.init(Specs.allocation(Specs.Balance, 1));
        (writerBuffer, writer) = Encoder.writeBalance(writer, writerBuffer, asset, amount);
        return Encoder.finish(writer, writerBuffer);
    }

    function appendHostAsset(uint host, bytes32 asset) external pure returns (bytes memory) {
        (bytes memory writerBuffer, uint writer) = Encoder.init(Specs.allocation(Specs.HostAsset, 1));
        (writerBuffer, writer) = Encoder.writeHostAsset(writer, writerBuffer, host, asset);
        return Encoder.finish(writer, writerBuffer);
    }

    function createAssetLiability(bytes32 asset, bytes32 liability) external pure returns (bytes memory) {
        return LegacyBlocks.createAssetLiability(asset, liability);
    }

    function appendAssetLiability(bytes32 asset, bytes32 liability) external pure returns (bytes memory) {
        (bytes memory writerBuffer, uint writer) = Encoder.init(Specs.allocation(Specs.AssetLiability, 1));
        (writerBuffer, writer) = Encoder.writeAssetLiability(writer, writerBuffer, asset, liability);
        return Encoder.finish(writer, writerBuffer);
    }

    function executionUnpackAssetLiability(
        bytes calldata input
    ) external view returns (bytes32 asset, bytes32 liability) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.AssetLiability, Specs.Empty);
        Execution memory exec = openInput(input, descriptor);
        return exec.unpackAssetLiability();
    }

    function writeHostAsset(uint offset, uint host, bytes32 asset) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.HostAsset);
        LegacyBlocks.writeHostAsset(dst, offset, host, asset);
    }

    function emptyWriter() external pure returns (uint i, uint len, uint length) {
        (bytes memory writerBuffer, uint writer) = Encoder.init(Specs.allocation(Specs.Bytes, 0));
        i = Cursors.position(writer);
        len = Cursors.limit(writer);
        length = writerBuffer.length;
    }

    /// @notice Reserve a lazily allocated buffer and expose its resulting metadata.
    function reserveBuffer(
        uint len,
        uint advance,
        uint touch
    ) external pure returns (uint i, uint next, uint capacity, uint physical) {
        uint cur = LegacyBuffers.cursor(len);
        bytes memory buffer;
        (cur, buffer, i) = LegacyBuffers.reserve(cur, buffer, advance, touch);
        next = Cursors.position(cur);
        capacity = Cursors.limit(cur);
        physical = buffer.length;
    }

    /// @notice Grow a buffer across two writes and return its finalized bytes.
    function growBuffer(bytes32 a, bytes32 b) external pure returns (bytes memory buffer) {
        uint cur = LegacyBuffers.cursor(32);
        uint i;
        (cur, buffer, i) = LegacyBuffers.reserve(cur, buffer, 32, 32);
        LegacyBuffers.write32(buffer, i, a);
        (cur, buffer, i) = LegacyBuffers.reserve(cur, buffer, 32, 32);
        LegacyBuffers.write32(buffer, i, b);
        return LegacyBuffers.finish(cur, buffer);
    }

    /// @notice Spend the value lane of `resources` and drain the remainder.
    function budgetUseResourceValue(uint resources) external payable returns (uint value, uint remaining) {
        Budget memory budget = Budgets.open();
        value = budget.useResourceValue(resources);
        remaining = budget.drain();
    }

    /// @notice Spend an exact value and drain the remainder.
    function budgetUseValue(uint value) external payable returns (uint used, uint remaining) {
        Budget memory budget = Budgets.open();
        used = budget.useValue(value);
        remaining = budget.drain();
    }

    /// @notice Add trusted value to a standalone budget.
    function budgetAddValue(uint initial, uint value) external pure returns (uint remaining) {
        Budget memory budget;
        budget.remaining = initial;
        budget.addValue(value);
        remaining = budget.remaining;
    }

    /// @notice Add trusted value to an execution budget.
    function executionAddToBudget(uint initial, uint value) external pure returns (uint remaining) {
        Execution memory exec;
        exec.budget = initial;
        exec.addToBudget(value);
        remaining = exec.budget;
    }

    /// @notice Drain a standalone budget and expose its cleared state.
    function budgetDrain() external payable returns (uint drained, uint remaining) {
        Budget memory budget = Budgets.open();
        drained = budget.drain();
        remaining = budget.remaining;
    }

    /// @notice Detach an execution budget and expose both resulting balances.
    function takeBudget() external payable returns (uint execution, uint detached) {
        Execution memory exec = Executions.open();
        Budget memory budget = Executions.takeBudget(exec);
        execution = exec.budget;
        detached = budget.remaining;
    }

    /// @notice Drain an execution budget and expose both resulting values.
    function drainBudget() external payable returns (uint execution, uint drained) {
        Execution memory exec = Executions.open();
        drained = Executions.drainBudget(exec);
        execution = exec.budget;
    }

    function growSecond32(bytes32 value) external pure returns (bytes memory) {
        uint spec = Specs.create(TestKey, 32, 32, 32);
        (bytes memory writerBuffer, uint writer) = Encoder.init(Specs.allocation(spec, 1));
        (writerBuffer, writer) = Encoder.writeBlock(writer, writerBuffer, Specs.key(spec), abi.encode(value));
        (writerBuffer, writer) = Encoder.writeBlock(writer, writerBuffer, Specs.key(spec), abi.encode(value));
        return Encoder.finish(writer, writerBuffer);
    }

    function rejectOversizedDynamic(bytes memory data) external pure returns (bytes memory) {
        uint spec = Specs.create(Specs.key(Specs.Bytes), 32, 32, 32);
        (bytes memory writerBuffer, uint writer) = Encoder.init(Specs.allocation(spec, 1));
        Specs.validate(spec, data.length);
        (writerBuffer, writer) = Encoder.writeBlock(writer, writerBuffer, Specs.key(spec), data);
        return Encoder.finish(writer, writerBuffer);
    }

    function rejectOutOfRange(bytes memory data) external pure returns (bytes memory) {
        uint spec = Specs.create(Specs.key(Specs.Bytes), 2, 4, 32);
        (bytes memory writerBuffer, uint writer) = Encoder.init(Specs.allocation(spec, 1));
        Specs.validate(spec, data.length);
        (writerBuffer, writer) = Encoder.writeBlock(writer, writerBuffer, Specs.key(spec), data);
        return Encoder.finish(writer, writerBuffer);
    }

    function read32(bytes calldata source, uint i) external pure returns (bytes32) {
        return LegacyBlocks.read32(position(source) + i);
    }

    function readEqualAt32(bytes calldata source, uint i, uint j) external pure returns (bytes32) {
        uint abs = position(source);
        return LegacyBlocks.readEqualAt32(abs + i, abs + j);
    }

    function readNotEqualAt32(bytes calldata source, uint i, uint j) external pure returns (bytes32, bytes32) {
        uint abs = position(source);
        return LegacyBlocks.readNotEqualAt32(abs + i, abs + j);
    }

    function readLtAt32(bytes calldata source, uint i, uint j) external pure returns (bytes32, bytes32) {
        uint abs = position(source);
        return LegacyBlocks.readLtAt32(abs + i, abs + j);
    }

    function readLeAt32(bytes calldata source, uint i, uint j) external pure returns (bytes32, bytes32) {
        uint abs = position(source);
        return LegacyBlocks.readLeAt32(abs + i, abs + j);
    }

    function readGtAt32(bytes calldata source, uint i, uint j) external pure returns (bytes32, bytes32) {
        uint abs = position(source);
        return LegacyBlocks.readGtAt32(abs + i, abs + j);
    }

    function readGeAt32(bytes calldata source, uint i, uint j) external pure returns (bytes32, bytes32) {
        uint abs = position(source);
        return LegacyBlocks.readGeAt32(abs + i, abs + j);
    }

    function readWidths(
        bytes calldata source,
        uint i
    ) external pure returns (bytes1, bytes2, bytes4, bytes8, bytes16, bytes32) {
        uint abs = position(source) + i;
        return (
            LegacyBlocks.read1(abs),
            LegacyBlocks.read2(abs),
            LegacyBlocks.read4(abs),
            LegacyBlocks.read8(abs),
            LegacyBlocks.read16(abs),
            LegacyBlocks.read32(abs)
        );
    }

    function expectWidth(bytes calldata source, uint i, uint width, bytes32 expected) external pure {
        uint abs = position(source) + i;
        if (width == 1) {
            LegacyBlocks.expect1(abs, bytes1(expected));
            return;
        }
        if (width == 2) {
            LegacyBlocks.expect2(abs, bytes2(expected));
            return;
        }
        if (width == 4) {
            LegacyBlocks.expect4(abs, bytes4(expected));
            return;
        }
        if (width == 8) {
            LegacyBlocks.expect8(abs, bytes8(expected));
            return;
        }
        if (width == 16) {
            LegacyBlocks.expect16(abs, bytes16(expected));
            return;
        }
        if (width == 32) {
            LegacyBlocks.expect32(abs, expected);
            return;
        }
        revert UnexpectedValue();
    }

    function read32AsUint(bytes calldata source, uint i) external pure returns (uint) {
        return uint(LegacyBlocks.read32(position(source) + i));
    }

    function enterAbsolute(
        bytes calldata source,
        uint spec
    ) external pure returns (uint i, uint end) {
        uint head = position(source);
        (uint abs, uint limit) = LegacyBlocks.enter(head, spec);
        i = abs - head;
        end = limit - head;
    }

    function descendAbsolute(
        bytes calldata source,
        uint parent,
        uint child
    ) external pure returns (uint body, uint end, uint outer) {
        uint base = position(source);
        (body, end, outer) = LegacyBlocks.descend(base, parent, child);
        body -= base;
        end -= base;
        outer -= base;
    }

    function enterAssetAmountAbsolute(
        bytes calldata source,
        uint spec,
        uint amount
    ) external pure returns (uint body, uint next, uint end) {
        uint base = position(source);
        (body, next, end) = LegacyBlocks.enter(base, spec, amount);
        body -= base;
        next -= base;
        end -= base;
    }

    function enterKeyAssetAmountAbsolute(
        bytes calldata source,
        bytes4 key,
        uint amount
    ) external pure returns (uint body, uint next, uint end) {
        uint base = position(source);
        (body, next, end) = LegacyBlocks.enter(base, key, amount);
        body -= base;
        next -= base;
        end -= base;
    }

    function enterSlice(
        bytes calldata source,
        uint spec
    ) external pure returns (uint body, uint end, uint limit) {
        uint base = position(source);
        (body, end, limit) = LegacyBlocks.enter(source, spec);
        body -= base;
        end -= base;
        limit -= base;
    }

    function exactBlock(
        bytes calldata source,
        uint spec
    ) external pure returns (uint body) {
        uint base = position(source);
        body = LegacyBlocks.exact(source, spec);
        body -= base;
    }

    function headerAbsolute(bytes calldata source) external pure returns (bytes4 key, uint len) {
        return LegacyBlocks.header(position(source));
    }

    function headerAbsolute(bytes calldata source, bytes4 key) external pure returns (uint len) {
        return LegacyBlocks.header(position(source), key);
    }

    function writeBalance(
        uint offset,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Balance);
        LegacyBlocks.writeBalance(dst, offset, asset, amount);
    }

    function writePosition(
        uint offset,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Position);
        LegacyBlocks.writePosition(dst, offset, asset, amount, liability, debt, bytes32(0));
    }

    function writeList(uint offset, bytes memory value) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Header + value.length);
        LegacyBlocks.writeList(dst, offset, value);
    }

    function writeBytes(uint offset, bytes memory value) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Header + value.length);
        LegacyBlocks.writeBytes(dst, offset, value);
    }

    function writeString(uint offset, string memory value) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Header + bytes(value).length);
        LegacyBlocks.writeString(dst, offset, value);
    }

    function writeStep(
        uint offset,
        uint cmd,
        uint value,
        bytes memory input
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Step + input.length);
        LegacyBlocks.writeStep(dst, offset, cmd, value, input);
    }

    function writeCall(
        uint offset,
        uint target,
        uint resources,
        bytes memory payload
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B64 + Sizes.Header + payload.length);
        LegacyBlocks.writeCall(dst, offset, target, resources, payload);
    }

    function writeRelay(
        uint offset,
        uint portal,
        uint resources,
        bytes memory steps
    ) external pure returns (bytes memory dst) {
        bytes memory input = abi.encode(portal, resources);
        dst = new bytes(offset + 3 * Sizes.Header + input.length + steps.length);
        LegacyBlocks.writeRelay(dst, offset, input, steps);
    }

    function writeDispatch(
        uint offset,
        uint portal,
        uint resources,
        bytes memory payload
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B64 + Sizes.Header + payload.length);
        LegacyBlocks.writeDispatch(dst, offset, portal, resources, payload);
    }

    function writeContext(
        uint offset,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B32 + 2 * Sizes.Header + state.length + input.length);
        LegacyBlocks.writeContext(dst, offset, account, state, input);
    }

    function writeRecover(
        uint offset,
        uint handler,
        uint resources,
        bytes32 key,
        bytes memory witness
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B96 + Sizes.Header + witness.length);
        LegacyBlocks.writeRecover(dst, offset, handler, resources, key, witness);
    }

    function writeLabel(
        uint offset,
        bytes32 namespace,
        string memory name
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B32 + Sizes.Header + bytes(name).length);
        LegacyBlocks.writeLabel(dst, offset, namespace, name);
    }

    function writeSchema(
        uint offset,
        uint spec,
        string memory body
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B32 + Sizes.Header + bytes(body).length);
        LegacyBlocks.writeSchema(dst, offset, spec, body);
    }

    function position(bytes calldata source) private pure returns (uint abs) {
        assembly ("memory-safe") {
            abs := source.offset
        }
    }

    function unpackAccount(bytes calldata source) external pure returns (bytes32) {
        return LegacyBlocks.unpackAccount(position(source));
    }

    function unpackAsset(bytes calldata source) external pure returns (bytes32) {
        return LegacyBlocks.unpackAsset(position(source));
    }

    function unpackNode(bytes calldata source) external pure returns (uint) {
        return LegacyBlocks.unpackNode(position(source));
    }

    function unpackStatus(bytes calldata source) external pure returns (uint) {
        return LegacyBlocks.unpackStatus(position(source));
    }

    function unpackBootstrap(bytes calldata source) external pure returns (bytes32, uint, uint) {
        return LegacyBlocks.unpackBootstrap(position(source));
    }

    function unpackAssetAmount(bytes calldata source) external pure returns (bytes32, uint) {
        return LegacyBlocks.unpackAssetAmount(position(source));
    }

    function unpackBalance(bytes calldata source) external pure returns (bytes32, uint) {
        return LegacyBlocks.unpackBalance(position(source));
    }

    function unpackPosition(bytes calldata source) external pure returns (bytes32, uint, bytes32, uint, bytes32) {
        return LegacyBlocks.unpackPosition(position(source));
    }

    function unpackAccountAsset(bytes calldata source) external pure returns (bytes32, bytes32) {
        return LegacyBlocks.unpackAccountAsset(position(source));
    }

    function unpackAssetLiability(bytes calldata source) external pure returns (bytes32, bytes32) {
        return LegacyBlocks.unpackAssetLiability(position(source));
    }

    function unpackHostAsset(bytes calldata source) external pure returns (uint, bytes32) {
        return LegacyBlocks.unpackHostAsset(position(source));
    }

    function unpackAllocation(bytes calldata source) external pure returns (uint, bytes32, uint) {
        return LegacyBlocks.unpackAllocation(position(source));
    }

    function unpackAllowance(bytes calldata source) external pure returns (uint, bytes32, uint) {
        return LegacyBlocks.unpackAllowance(position(source));
    }

    function unpackCustody(bytes calldata source) external pure returns (uint, bytes32, uint) {
        return LegacyBlocks.unpackCustody(position(source));
    }

    function unpackAccountAmount(bytes calldata source) external pure returns (bytes32, bytes32, uint) {
        return LegacyBlocks.unpackAccountAmount(position(source));
    }

    function unpackHostAmount(bytes calldata source) external pure returns (uint, bytes32, uint) {
        return LegacyBlocks.unpackHostAmount(position(source));
    }

    function unpackHostAccountAsset(bytes calldata source) external pure returns (uint, bytes32, bytes32) {
        return LegacyBlocks.unpackHostAccountAsset(position(source));
    }

    function unpackTransaction(
        bytes calldata source
    ) external pure returns (bytes32, bytes32, bytes32, uint) {
        return LegacyBlocks.unpackTransaction(position(source));
    }

    function unpackHostAccountAmount(
        bytes calldata source
    ) external pure returns (uint, bytes32, bytes32, uint) {
        return LegacyBlocks.unpackHostAccountAmount(position(source));
    }

    function unpackList(bytes calldata source) external pure returns (bytes memory data, uint length) {
        uint abs = position(source);
        bytes calldata value;
        uint end;
        (value, end) = LegacyBlocks.unpackList(abs);
        data = value;
        length = end - abs;
    }

    function unpackBytes(bytes calldata source) external pure returns (bytes memory data, uint length) {
        uint abs = position(source);
        bytes calldata value;
        uint end;
        (value, end) = LegacyBlocks.unpackBytes(abs);
        data = value;
        length = end - abs;
    }

    function unpackString(bytes calldata source) external pure returns (bytes memory data, uint length) {
        uint abs = position(source);
        bytes calldata value;
        uint end;
        (value, end) = LegacyBlocks.unpackString(abs);
        data = value;
        length = end - abs;
    }

    function writeTransaction(
        uint offset,
        bytes32 from,
        bytes32 to,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Transaction);
        LegacyBlocks.writeTransaction(dst, offset, from, to, asset, amount);
    }
}
