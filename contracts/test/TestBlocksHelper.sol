// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {UnexpectedValue} from "../utils/Errors.sol";

import {Blocks} from "../codec/Blocks.sol";
import {Buffers} from "../codec/Buffers.sol";
import {Sizes, Specs} from "../codec/Specs.sol";
import {Writer, Writers} from "../codec/Writers.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Cursors, Cur} from "../utils/Cursors.sol";
import {Flags} from "../utils/Flags.sol";
import {Budget, Budgets} from "../core/Budget.sol";
import {Action} from "../annotations/Action.sol";
import {Counterparty} from "../annotations/Counterparty.sol";

using Writers for Writer;
using Budgets for Budget;
using Executions for Execution;

contract TestBlocksHelper is Action, Counterparty {
    bytes4 private constant TestKey = bytes4(uint32(1));

    function openInput(
        bytes calldata input,
        uint descriptor
    ) private view returns (Execution memory exec) {
        exec.openInput(descriptor, msg.value, input);
    }

    function openState(
        bytes calldata state,
        uint descriptor
    ) private view returns (Execution memory exec) {
        exec.open(descriptor, 0, msg.value, state, msg.data[0:0]);
    }

    function openExecution(
        bytes calldata state,
        bytes calldata input,
        uint descriptor
    ) private view returns (Execution memory exec) {
        exec.open(descriptor, 0, msg.value, state, input);
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

    function publishAction(uint entity, uint value) external {
        action(entity, value);
    }

    function publishCounterparty(uint entity, bytes32 account) external {
        counterparty(entity, account);
    }

    function blockCapacity() external pure returns (uint) {
        return Specs.allocation(Specs.Balance, 6);
    }

    function describeSpecs(uint state, uint input, uint output) external pure returns (uint) {
        return Executions.describe(state, input, output, 0);
    }

    function descriptorWord() external pure returns (uint) {
        return Executions.describe(
            Specs.Balance,
            Specs.Asset,
            Specs.Amount,
            Flags.AdminFunded
        );
    }

    function descriptorOpens(
        bytes calldata state,
        bytes calldata input
    ) external pure returns (uint stateCursor, uint stateWriter, uint inputCursor, uint inputWriter) {
        uint descriptor = Executions.describe(
            Specs.Balance,
            Specs.Asset,
            Specs.Amount,
            0
        );
        Execution memory stateExec;
        Execution memory inputExec;
        stateExec.open(descriptor, 0, 0, state, msg.data[0:0]);
        inputExec.openInput(descriptor, 0, input);
        (stateCursor, stateWriter) = (stateExec.decoders, stateExec.writer);
        (inputCursor, inputWriter) = (inputExec.decoders, inputExec.writer);
    }

    function executionWriterHint(
        bytes calldata state,
        bytes calldata input,
        uint stateSpec,
        uint inputSpec,
        uint outputSpec
    ) external view returns (uint len) {
        uint descriptor = Executions.describe(stateSpec, inputSpec, outputSpec, 0);
        Execution memory exec = openExecution(state, input, descriptor);
        len = Cursors.limit(exec.writer);
    }

    function executionOutputPosition(
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) external view returns (bytes memory output) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.Empty, Specs.Position, 0);
        Execution memory exec = openInput(msg.data[0:0], descriptor);
        Executions.outputPosition(exec, asset, amount, liability, debt, bytes32(0));
        output = Executions.finish(exec);
    }

    function executionOutputEmpty(bytes4 key) external view returns (bytes memory output) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.Empty, Specs.Balance, 0);
        Execution memory exec = openInput(msg.data[0:0], descriptor);
        Executions.outputEmpty(exec, key);
        output = Executions.finish(exec);
    }

    function executionOutputHostAsset(uint host, bytes32 asset) external view returns (bytes memory output) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.Empty, Specs.HostAsset, 0);
        Execution memory exec = openInput(msg.data[0:0], descriptor);
        Executions.outputHostAsset(exec, host, asset);
        output = Executions.finish(exec);
    }

    function executionUnpackPosition(
        bytes calldata state
    ) external view returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        uint descriptor = Executions.describe(Specs.Position, Specs.Empty, Specs.Empty, 0);
        Execution memory exec = openState(state, descriptor);
        return exec.unpackPosition();
    }

    function executionIsEmpty(bytes calldata input, uint spec, bytes4 key) external view returns (bool) {
        uint descriptor = Executions.describe(Specs.Empty, spec, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        return exec.isEmpty(key);
    }

    function executionTryConsumeEmpty(
        bytes calldata input,
        uint spec,
        bytes4 key
    ) external view returns (bool empty, bool more) {
        uint descriptor = Executions.describe(Specs.Empty, spec, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        empty = exec.tryConsumeEmpty(key);
        return (empty, Executions.more(exec));
    }

    function executionEnterAmount(
        bytes calldata state,
        bytes calldata input
    ) external view returns (bytes32 stateAsset, uint stateAmount, bytes32 inputAsset, uint inputAmount) {
        uint descriptor = Executions.describe(Specs.Balance, Specs.List, Specs.Empty, 0);
        Execution memory exec = openExecution(state, input, descriptor);
        (, uint end) = exec.enter(Specs.List);
        (stateAsset, stateAmount) = exec.unpackBalance();
        (inputAsset, inputAmount) = exec.unpackAmount();
        Executions.expectAbs(exec, end);
    }

    /// @notice Gas baseline reproducing the removed tagged, relative two-lane cursor path.
    /// @dev Kept to compare traversal correctness and detect material gas regressions.
    function legacyExecutionEnterAmount(
        bytes calldata state,
        bytes calldata input
    ) external pure returns (bytes32 stateAsset, uint stateAmount, bytes32 inputAsset, uint inputAmount) {
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
        (, next, end) = Blocks.enter(inputAbs, Specs.List, 0);
        decoders = legacySeekAbs(decoders, next);

        decoders = legacySelect(decoders, 2);
        uint stateAbs;
        (decoders, stateAbs) = legacyConsume(decoders, Sizes.Balance);
        (stateAsset, stateAmount) = Blocks.unpackBalance(stateAbs);

        decoders = legacySelect(decoders, 1);
        (decoders, inputAbs) = legacyConsume(decoders, Sizes.Amount);
        (inputAsset, inputAmount) = Blocks.unpackAmount(inputAbs);
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
        uint descriptor = Executions.describe(Specs.Empty, spec, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        Cur memory items = exec.list(spec);
        itemsLen = Cursors.limit(items.state) - Cursors.position(items.state);
        complete = !Executions.more(exec);
    }

    function executionTakeBlock(
        bytes calldata state,
        bytes calldata input,
        bytes4 inputKey,
        bytes4 expectedKey
    ) external view returns (bytes calldata data, bytes32 asset, uint amount, bool complete) {
        uint inputSpec = Specs.create(inputKey, 0, 0, 0);
        uint descriptor = Executions.describe(Specs.Balance, inputSpec, Specs.Empty, 0);
        Execution memory exec = openExecution(state, input, descriptor);
        data = exec.takeBlock(expectedKey);
        (asset, amount) = exec.unpackBalance();
        complete = !Executions.more(exec);
    }

    function executionRaw(
        bytes calldata state,
        bytes calldata input
    ) external view returns (bytes calldata beforeState, bytes calldata afterState, bytes calldata rawInput) {
        uint descriptor = Executions.describe(Specs.Balance, Specs.Amount, Specs.Empty, 0);
        Execution memory exec = openExecution(state, input, descriptor);
        beforeState = Executions.rawState(exec);
        exec.unpackBalance();
        afterState = Executions.rawState(exec);
        rawInput = Executions.rawInput(exec);
    }

    function executionRawEmptyState(
        bytes calldata input
    ) external view returns (bytes calldata state) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.Amount, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        return Executions.rawState(exec);
    }

    function executionTakeRawState(
        bytes calldata state
    ) external view returns (bytes calldata data, bool complete) {
        uint descriptor = Executions.describe(Specs.Balance, Specs.Empty, Specs.Empty, 0);
        Execution memory exec = openState(state, descriptor);
        data = Executions.takeRawState(exec);
        complete = !Executions.more(exec);
    }

    function executionTakeRawInput(
        bytes calldata input
    ) external view returns (bytes calldata data, bool complete) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.Amount, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        data = Executions.takeRawInput(exec);
        complete = !Executions.more(exec);
    }

    function executionForwardRaw(bytes calldata state, bytes calldata input, uint stateSpec, uint inputSpec)
        external view returns (bytes memory)
    {
        Execution memory exec = openExecution(state, input, Executions.describe(stateSpec, inputSpec, Specs.Empty, 0));
        Executions.takeRawState(exec);
        Executions.takeRawInput(exec);
        return exec.finish();
    }

    function executionFinishUnread(bytes calldata input) external view returns (bytes memory) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.Amount, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        return Executions.finish(exec);
    }

    function executionFinishUnreadState(bytes calldata state) external view returns (bytes memory) {
        uint descriptor = Executions.describe(Specs.Balance, Specs.Empty, Specs.Empty, 0);
        Execution memory exec = openState(state, descriptor);
        return Executions.finish(exec);
    }

    function executionEnterWords(bytes calldata input) external view returns (bytes32 first, bytes32 second) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.List, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        (, uint end) = exec.enter(Specs.List);
        first = exec.next32();
        second = exec.next32();
        Executions.expectAbs(exec, end);
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

        uint descriptor = Executions.describe(Specs.Empty, Specs.List, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        (body, end) = exec.enter(key, amount);
        i = exec.absolute();
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

        uint descriptor = Executions.describe(Specs.Empty, Specs.List, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        (, uint end) = exec.enter(Specs.List);
        abs = exec.absolute();
        exec.advance(amount);
        value = Blocks.read32(abs);
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

        uint descriptor = Executions.describe(Specs.Empty, Specs.List, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        (, uint end) = exec.enter(Specs.List);
        abs = exec.take(amount);
        value = Blocks.read32(abs);
        complete = amount == end - abs;
        return (abs - offset, value, complete);
    }

    function executionEnterSized(bytes calldata input)
        external
        view
        returns (bytes1 a, bytes2 b, bytes4 c, bytes8 d, bytes16 e, bytes32 f)
    {
        uint descriptor = Executions.describe(Specs.Empty, Specs.List, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        (, uint end) = exec.enter(Specs.List);
        a = exec.next1();
        b = exec.next2();
        c = exec.next4();
        d = exec.next8();
        e = exec.next16();
        f = exec.next32();
        Executions.expectAbs(exec, end);
    }

    function writerCopies(bytes calldata value) external pure returns (bytes memory) {
        Writer memory writer = Writers.init(0);
        writer.copyBlock(Specs.create(TestKey, 0, 0, 0), value);
        writer.copyList(value);
        writer.copyBytes(value);
        writer.copyStep(1, 2, value);
        writer.copyCall(3, 4, value);
        writer.appendRelay(abi.encode(uint(5), uint(6)), value);
        writer.copyDispatch(7, 8, value);
        writer.copyContext(bytes32(uint(9)), value, value);
        writer.copyRecover(10, 11, bytes32(uint(12)), value);
        return writer.finish();
    }

    function writerCopy(bytes calldata value) external pure returns (bytes memory) {
        Writer memory writer = Writers.init(0);
        writer.append32(bytes32(uint(0xaa) << 248), 1);
        writer.copy(value);
        writer.append32(bytes32(uint(0xbb) << 248), 1);
        return writer.finish();
    }

    function stringCopies(
        string calldata value
    ) external view returns (bytes memory factory, bytes memory written, bytes memory output) {
        factory = Blocks.createStringCopy(value);

        Writer memory writer = Writers.init(Specs.String, 1);
        writer.copyString(value);
        written = writer.finish();

        uint descriptor = Executions.describe(Specs.Empty, Specs.Empty, Specs.String, 0);
        Execution memory exec = openInput(msg.data[0:0], descriptor);
        Executions.outputCopyString(exec, value);
        output = Executions.finish(exec);
    }

    function bufferCopy(
        uint capacity,
        uint offset,
        bytes calldata value
    ) external pure returns (bytes memory buffer, uint next) {
        buffer = new bytes(capacity);
        next = Buffers.copy(buffer, offset, value);
    }

    function factoryCopies(bytes calldata value) external pure returns (bytes memory) {
        bytes memory leaves = bytes.concat(
            Blocks.createCopy(TestKey, value),
            Blocks.createListCopy(value),
            Blocks.createBytesCopy(value)
        );
        bytes memory composites = bytes.concat(
            Blocks.createStepCopy(1, 2, value),
            Blocks.createCallCopy(3, 4, value),
            Blocks.createRelay(abi.encode(uint(5), uint(6)), value),
            Blocks.createDispatchCopy(7, 8, value)
        );
        return bytes.concat(
            leaves,
            composites,
            Blocks.createContextCopy(bytes32(uint(9)), value, value),
            Blocks.createRecoverCopy(10, 11, bytes32(uint(12)), value)
        );
    }

    function executionCopies(bytes calldata value) external view returns (bytes memory) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.Empty, Specs.Bytes, 0);
        Execution memory exec = openInput(msg.data[0:0], descriptor);
        Executions.outputCopyBlock(exec, Specs.create(TestKey, 0, 0, 0), value);
        Executions.outputCopyList(exec, value);
        Executions.outputCopyBytes(exec, value);
        Executions.outputCopyStep(exec, 1, 2, value);
        Executions.outputCopyCall(exec, 3, 4, value);
        Executions.outputRelay(exec, abi.encode(uint(5), uint(6)), value);
        Executions.outputCopyDispatch(exec, 7, 8, value);
        Executions.outputCopyContext(exec, bytes32(uint(9)), value, value);
        Executions.outputCopyRecover(exec, 10, 11, bytes32(uint(12)), value);
        return Executions.finish(exec);
    }

    function lazyBalance(bytes32 asset, uint amount) external pure returns (bytes memory) {
        Writer memory writer = Writers.init(Specs.Balance, 1);
        writer.appendBalance(asset, amount);
        return writer.finish();
    }

    function appendHostAsset(uint host, bytes32 asset) external pure returns (bytes memory) {
        Writer memory writer = Writers.init(Specs.HostAsset, 1);
        writer.appendHostAsset(host, asset);
        return writer.finish();
    }

    function createAssetLiability(bytes32 asset, bytes32 liability) external pure returns (bytes memory) {
        return Blocks.createAssetLiability(asset, liability);
    }

    function appendAssetLiability(bytes32 asset, bytes32 liability) external pure returns (bytes memory) {
        Writer memory writer = Writers.init(Specs.AssetLiability, 1);
        writer.appendAssetLiability(asset, liability);
        return writer.finish();
    }

    function executionUnpackAssetLiability(
        bytes calldata input
    ) external view returns (bytes32 asset, bytes32 liability) {
        uint descriptor = Executions.describe(Specs.Empty, Specs.AssetLiability, Specs.Empty, 0);
        Execution memory exec = openInput(input, descriptor);
        return exec.unpackAssetLiability();
    }

    function writeHostAsset(uint offset, uint host, bytes32 asset) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.HostAsset);
        Blocks.writeHostAsset(dst, offset, host, asset);
    }

    function emptyWriter() external pure returns (uint i, uint len, uint length) {
        Writer memory writer = Writers.init(Specs.Bytes, 0);
        i = Cursors.position(writer.cur);
        len = Cursors.limit(writer.cur);
        length = writer.dst.length;
    }

    /// @notice Reserve a lazily allocated buffer and expose its resulting metadata.
    function reserveBuffer(
        uint len,
        uint advance,
        uint touch
    ) external pure returns (uint i, uint next, uint capacity, uint physical) {
        uint cur = Buffers.cursor(len);
        bytes memory buffer;
        (cur, buffer, i) = Buffers.reserve(cur, buffer, advance, touch);
        next = Cursors.position(cur);
        capacity = Cursors.limit(cur);
        physical = buffer.length;
    }

    /// @notice Grow a buffer across two writes and return its finalized bytes.
    function growBuffer(bytes32 a, bytes32 b) external pure returns (bytes memory buffer) {
        uint cur = Buffers.cursor(32);
        uint i;
        (cur, buffer, i) = Buffers.reserve(cur, buffer, 32, 32);
        Buffers.write32(buffer, i, a);
        (cur, buffer, i) = Buffers.reserve(cur, buffer, 32, 32);
        Buffers.write32(buffer, i, b);
        return Buffers.finish(cur, buffer);
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
    function executionAddValue(uint initial, uint value) external pure returns (uint remaining) {
        Execution memory exec;
        exec.budget = initial;
        exec.addValue(value);
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
        Writer memory writer = Writers.init(spec, 1);
        writer.appendBlock32(spec, value);
        writer.appendBlock32(spec, value);
        return writer.finish();
    }

    function rejectOversizedDynamic(bytes memory data) external pure returns (bytes memory) {
        uint spec = Specs.create(Specs.key(Specs.Bytes), 32, 32, 32);
        Writer memory writer = Writers.init(spec, 1);
        writer.appendBlock(spec, data);
        return writer.finish();
    }

    function rejectOutOfRange(bytes memory data) external pure returns (bytes memory) {
        uint spec = Specs.create(Specs.key(Specs.Bytes), 2, 4, 32);
        Writer memory writer = Writers.init(spec, 1);
        writer.appendBlock(spec, data);
        return writer.finish();
    }

    function read32(bytes calldata source, uint i) external pure returns (bytes32) {
        return Blocks.read32(position(source) + i);
    }

    function readWidths(
        bytes calldata source,
        uint i
    ) external pure returns (bytes1, bytes2, bytes4, bytes8, bytes16, bytes32) {
        uint abs = position(source) + i;
        return (
            Blocks.read1(abs),
            Blocks.read2(abs),
            Blocks.read4(abs),
            Blocks.read8(abs),
            Blocks.read16(abs),
            Blocks.read32(abs)
        );
    }

    function requireWidth(bytes calldata source, uint i, uint width, bytes32 expected) external pure {
        uint abs = position(source) + i;
        if (width == 1) {
            Blocks.require1(abs, bytes1(expected));
            return;
        }
        if (width == 2) {
            Blocks.require2(abs, bytes2(expected));
            return;
        }
        if (width == 4) {
            Blocks.require4(abs, bytes4(expected));
            return;
        }
        if (width == 8) {
            Blocks.require8(abs, bytes8(expected));
            return;
        }
        if (width == 16) {
            Blocks.require16(abs, bytes16(expected));
            return;
        }
        if (width == 32) {
            Blocks.require32(abs, expected);
            return;
        }
        revert UnexpectedValue();
    }

    function read32AsUint(bytes calldata source, uint i) external pure returns (uint) {
        return uint(Blocks.read32(position(source) + i));
    }

    function enterAbsolute(
        bytes calldata source,
        uint spec
    ) external pure returns (uint i, uint end) {
        uint head = position(source);
        (uint abs, uint limit) = Blocks.enter(head, spec);
        i = abs - head;
        end = limit - head;
    }

    function enterAmountAbsolute(
        bytes calldata source,
        uint spec,
        uint amount
    ) external pure returns (uint body, uint next, uint end) {
        uint base = position(source);
        (body, next, end) = Blocks.enter(base, spec, amount);
        body -= base;
        next -= base;
        end -= base;
    }

    function enterKeyAmountAbsolute(
        bytes calldata source,
        bytes4 key,
        uint amount
    ) external pure returns (uint body, uint next, uint end) {
        uint base = position(source);
        (body, next, end) = Blocks.enter(base, key, amount);
        body -= base;
        next -= base;
        end -= base;
    }

    function enterSlice(
        bytes calldata source,
        uint spec
    ) external pure returns (uint body, uint end, uint limit) {
        uint base = position(source);
        (body, end, limit) = Blocks.enter(source, spec);
        body -= base;
        end -= base;
        limit -= base;
    }

    function exactBlock(
        bytes calldata source,
        uint spec
    ) external pure returns (uint body) {
        uint base = position(source);
        body = Blocks.exact(source, spec);
        body -= base;
    }

    function headerAbsolute(bytes calldata source) external pure returns (bytes4 key, uint len) {
        return Blocks.header(position(source));
    }

    function headerAbsolute(bytes calldata source, bytes4 key) external pure returns (uint len) {
        return Blocks.header(position(source), key);
    }

    function writeBalance(
        uint offset,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Balance);
        Blocks.writeBalance(dst, offset, asset, amount);
    }

    function writePosition(
        uint offset,
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Position);
        Blocks.writePosition(dst, offset, asset, amount, liability, debt, bytes32(0));
    }

    function writeList(uint offset, bytes memory value) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Header + value.length);
        Blocks.writeList(dst, offset, value);
    }

    function writeBytes(uint offset, bytes memory value) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Header + value.length);
        Blocks.writeBytes(dst, offset, value);
    }

    function writeString(uint offset, string memory value) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Header + bytes(value).length);
        Blocks.writeString(dst, offset, value);
    }

    function writeStep(
        uint offset,
        uint cmd,
        uint value,
        bytes memory input
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.Step + input.length);
        Blocks.writeStep(dst, offset, cmd, value, input);
    }

    function writeCall(
        uint offset,
        uint target,
        uint resources,
        bytes memory payload
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B64 + Sizes.Header + payload.length);
        Blocks.writeCall(dst, offset, target, resources, payload);
    }

    function writeRelay(
        uint offset,
        uint portal,
        uint resources,
        bytes memory steps
    ) external pure returns (bytes memory dst) {
        bytes memory input = abi.encode(portal, resources);
        dst = new bytes(offset + 3 * Sizes.Header + input.length + steps.length);
        Blocks.writeRelay(dst, offset, input, steps);
    }

    function writeDispatch(
        uint offset,
        uint portal,
        uint resources,
        bytes memory payload
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B64 + Sizes.Header + payload.length);
        Blocks.writeDispatch(dst, offset, portal, resources, payload);
    }

    function writeContext(
        uint offset,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B32 + 2 * Sizes.Header + state.length + input.length);
        Blocks.writeContext(dst, offset, account, state, input);
    }

    function writeRecover(
        uint offset,
        uint handler,
        uint resources,
        bytes32 key,
        bytes memory witness
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B96 + Sizes.Header + witness.length);
        Blocks.writeRecover(dst, offset, handler, resources, key, witness);
    }

    function writeLabel(
        uint offset,
        bytes32 namespace,
        string memory name
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B32 + Sizes.Header + bytes(name).length);
        Blocks.writeLabel(dst, offset, namespace, name);
    }

    function writeSchema(
        uint offset,
        uint spec,
        string memory body,
        bytes32 name
    ) external pure returns (bytes memory dst) {
        dst = new bytes(offset + Sizes.B64 + Sizes.Header + bytes(body).length);
        Blocks.writeSchema(dst, offset, spec, body, name);
    }

    function position(bytes calldata source) private pure returns (uint abs) {
        assembly ("memory-safe") {
            abs := source.offset
        }
    }

    function unpackAccount(bytes calldata source) external pure returns (bytes32) {
        return Blocks.unpackAccount(position(source));
    }

    function unpackAsset(bytes calldata source) external pure returns (bytes32) {
        return Blocks.unpackAsset(position(source));
    }

    function unpackNode(bytes calldata source) external pure returns (uint) {
        return Blocks.unpackNode(position(source));
    }

    function unpackStatus(bytes calldata source) external pure returns (uint) {
        return Blocks.unpackStatus(position(source));
    }

    function unpackBootstrap(bytes calldata source) external pure returns (bytes32, uint, uint) {
        return Blocks.unpackBootstrap(position(source));
    }

    function unpackAmount(bytes calldata source) external pure returns (bytes32, uint) {
        return Blocks.unpackAmount(position(source));
    }

    function unpackBalance(bytes calldata source) external pure returns (bytes32, uint) {
        return Blocks.unpackBalance(position(source));
    }

    function unpackPosition(bytes calldata source) external pure returns (bytes32, uint, bytes32, uint, bytes32) {
        return Blocks.unpackPosition(position(source));
    }

    function unpackAccountAsset(bytes calldata source) external pure returns (bytes32, bytes32) {
        return Blocks.unpackAccountAsset(position(source));
    }

    function unpackAssetLiability(bytes calldata source) external pure returns (bytes32, bytes32) {
        return Blocks.unpackAssetLiability(position(source));
    }

    function unpackHostAsset(bytes calldata source) external pure returns (uint, bytes32) {
        return Blocks.unpackHostAsset(position(source));
    }

    function unpackAllocation(bytes calldata source) external pure returns (uint, bytes32, uint) {
        return Blocks.unpackAllocation(position(source));
    }

    function unpackAllowance(bytes calldata source) external pure returns (uint, bytes32, uint) {
        return Blocks.unpackAllowance(position(source));
    }

    function unpackCustody(bytes calldata source) external pure returns (uint, bytes32, uint) {
        return Blocks.unpackCustody(position(source));
    }

    function unpackAccountAmount(bytes calldata source) external pure returns (bytes32, bytes32, uint) {
        return Blocks.unpackAccountAmount(position(source));
    }

    function unpackHostAmount(bytes calldata source) external pure returns (uint, bytes32, uint) {
        return Blocks.unpackHostAmount(position(source));
    }

    function unpackHostAccountAsset(bytes calldata source) external pure returns (uint, bytes32, bytes32) {
        return Blocks.unpackHostAccountAsset(position(source));
    }

    function unpackTransaction(
        bytes calldata source
    ) external pure returns (bytes32, bytes32, bytes32, uint) {
        return Blocks.unpackTransaction(position(source));
    }

    function unpackHostAccountAmount(
        bytes calldata source
    ) external pure returns (uint, bytes32, bytes32, uint) {
        return Blocks.unpackHostAccountAmount(position(source));
    }

    function unpackList(bytes calldata source) external pure returns (bytes memory data, uint length) {
        uint abs = position(source);
        bytes calldata value;
        uint end;
        (value, end) = Blocks.unpackList(abs);
        data = value;
        length = end - abs;
    }

    function unpackBytes(bytes calldata source) external pure returns (bytes memory data, uint length) {
        uint abs = position(source);
        bytes calldata value;
        uint end;
        (value, end) = Blocks.unpackBytes(abs);
        data = value;
        length = end - abs;
    }

    function unpackString(bytes calldata source) external pure returns (bytes memory data, uint length) {
        uint abs = position(source);
        bytes calldata value;
        uint end;
        (value, end) = Blocks.unpackString(abs);
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
        Blocks.writeTransaction(dst, offset, from, to, asset, amount);
    }
}
