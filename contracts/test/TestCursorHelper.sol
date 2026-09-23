// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { Position, Tx } from "../core/Types.sol";
import { Specs } from "../codec/Specs.sol";
import { Blocks, Cur, Decoders, Memory, Sizes, Writer } from "../Codec.sol";
import {Cursors} from "../utils/Cursors.sol";
import {OutOfBounds} from "../utils/Errors.sol";
import { Writers } from "../codec/Writers.sol";

using Decoders for Cur;
using Writers for Writer;
using Cursors for uint;

contract TestCursorHelper {
    function relativePosition(Cur memory cur, bytes calldata source) private pure returns (uint) {
        return cur.state.position() - Cursors.base(source);
    }

    function testSpanMeta(
        uint8 flags
    ) external pure returns (uint cur, uint8 decodedFlags) {
        cur = Cursors.create(0, 0, flags);
        decodedFlags = uint8(cur >> 64);
    }

    function testCursorBounds() external pure returns (uint abs, uint end) {
        return Cursors.create(10, 30, 0).seek(15).bounds();
    }

    function testCalldataBounds(bytes calldata source, uint size) external pure returns (uint abs, uint end) {
        return Cursors.bounds(source, size);
    }

    /// @notice Exercise cursor consumption and report the resulting position.
    function testCursorNavigation(
        uint offset,
        uint len,
        uint i,
        uint amount
    ) external pure returns (uint next, uint abs, bool more) {
        uint cur = Cursors.create(offset, offset + len, 0).seek(offset + i);
        (cur, abs) = cur.consume(amount);
        next = cur.position() - offset;
        more = cur.more();
    }

    /// @notice Exercise cursor resizing at an existing position.
    function testCursorResize(uint len, uint i, uint resized) external pure returns (uint next, uint capacity) {
        uint cur = Cursors.create(0, len, 0).seek(i).resize(resized);
        next = cur.position();
        capacity = cur.limit();
    }

    /// @notice Decode through the absolute generic cursor for gas regression coverage.
    function absoluteCursorBytes(bytes calldata source) external pure returns (bytes32 digest, uint next) {
        Cur memory cur = Decoders.open(source);
        bytes calldata a = cur.unpackBytes();
        bytes calldata b = cur.unpackBytes();
        bytes calldata c = cur.unpackBytes();
        digest = keccak256(a) ^ keccak256(b) ^ keccak256(c);
        next = cur.state.position();
    }

    /// @notice Reproduce the removed relative generic cursor path as a gas baseline.
    function relativeCursorBytes(bytes calldata source) external pure returns (bytes32 digest, uint next) {
        uint cur;
        assembly ("memory-safe") {
            cur := or(shl(32, source.offset), shl(64, source.length))
        }
        bytes calldata a;
        bytes calldata b;
        bytes calldata c;
        (cur, a) = relativeBytes(cur);
        (cur, b) = relativeBytes(cur);
        (cur, c) = relativeBytes(cur);
        digest = keccak256(a) ^ keccak256(b) ^ keccak256(c);
        next = uint32(cur >> 32) + uint32(cur);
    }

    function relativeBytes(uint cur) private pure returns (uint updated, bytes calldata value) {
        uint position = uint32(cur);
        uint len = uint32(cur >> 64);
        uint abs = uint32(cur >> 32) + position;
        uint end;
        (value, end) = Blocks.unpackBytes(abs);
        uint offset = uint32(cur >> 32);
        if (end < offset) revert OutOfBounds();
        uint nextPosition = end - offset;
        if (nextPosition < position || nextPosition > len) revert OutOfBounds();
        updated = (cur & ~uint(type(uint32).max)) | nextPosition;
    }

    function testWriteBalanceBlock(bytes32 asset, uint amount) external pure returns (bytes memory) {
        Writer memory w = Writers.init(Specs.Balance, 1);
        w.appendBalance(asset, amount);
        return w.finish();
    }

    function testWriteEmptyBlock(bytes4 key) external pure returns (bytes memory) {
        Writer memory w = Writers.init(Specs.Balance, 1);
        w.appendEmpty(key);
        return w.finish();
    }

    function testWriteCustodyBlock(
        uint host_,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory) {
        Writer memory w = Writers.init(Specs.Custody, 1);
        w.appendCustody(host_, asset, amount);
        return w.finish();
    }

    function testWritePositionBlock(
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) external pure returns (bytes memory) {
        Writer memory w = Writers.init(Specs.Position, 1);
        w.appendPosition(asset, amount, liability, debt, bytes32(0));
        return w.finish();
    }

    function testWritePositionCounterparty(bytes32 counterparty) external pure returns (bytes memory) {
        return Blocks.createPosition(bytes32(0), 0, bytes32(0), 0, counterparty);
    }

    function testWritePositionStructBlock(
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) external pure returns (bytes memory) {
        Writer memory w = Writers.init(Specs.Position, 1);
        w.appendPosition(Position(asset, amount, liability, debt, bytes32(0)));
        return w.finish();
    }

    function testWriteTxBlock(
        bytes32 from_,
        bytes32 to_,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory) {
        Writer memory w = Writers.init(Specs.Transaction, 1);
        w.appendTransaction(from_, to_, asset, amount);
        return w.finish();
    }

    function testWriteTxStructBlock(
        bytes32 from_,
        bytes32 to_,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory) {
        Writer memory w = Writers.init(Specs.Transaction, 1);
        w.appendTransaction(Tx({ from: from_, to: to_, asset: asset, amount: amount }));
        return w.finish();
    }

    function testToDispatchBlock(uint portal, uint resources, bytes memory payload) external pure returns (bytes memory) {
        return Blocks.createDispatch(portal, resources, payload);
    }

    function testToBalanceBlock(bytes32 asset, uint amount) external pure returns (bytes memory) {
        return Blocks.createBalance(asset, amount);
    }

    function testToAmountBlock(bytes32 asset, uint amount) external pure returns (bytes memory) {
        return Blocks.createAmount(asset, amount);
    }

    function testToBootstrapBlock(bytes32 asset, uint amount, uint budget) external pure returns (bytes memory) {
        return Blocks.createBootstrap(asset, amount, budget);
    }

    function testToEmptyBlock(bytes4 key) external pure returns (bytes memory) {
        return Blocks.createEmpty(key);
    }

    function testToLabelBlock(bytes32 namespace, string memory name) external pure returns (bytes memory) {
        return Blocks.createLabel(namespace, name);
    }

    function testToActionBlock(uint value) external pure returns (bytes memory) {
        return Blocks.createAction(value);
    }

    function testToCounterpartyBlock(bytes32 account) external pure returns (bytes memory) {
        return Blocks.createCounterparty(account);
    }

    function testToSchemaBlock(uint spec, string memory body, bytes32 name) external pure returns (bytes memory) {
        return Blocks.createSchema(spec, body, name);
    }

    function testToSchemaBlock(uint spec, string memory body) external pure returns (bytes memory) {
        return Blocks.createSchema(spec, body);
    }

    function testToCustodyBlock(
        uint host_,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory) {
        return Blocks.createCustody(host_, asset, amount);
    }

    function testToPositionBlock(
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) external pure returns (bytes memory) {
        return Blocks.createPosition(asset, amount, liability, debt, bytes32(0));
    }

    function testToTransactionBlock(
        bytes32 from_,
        bytes32 to_,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory) {
        return Blocks.createTransaction(from_, to_, asset, amount);
    }

    function testWriterFinishEmpty() external pure returns (bytes memory) {
        Writer memory w = Writers.init(Specs.Balance, 1);
        return w.finish();
    }

    function testWriterFinish(bytes32 asset, uint amount) external pure returns (bytes memory) {
        Writer memory w = Writers.init(Specs.Balance, 2);
        w.appendBalance(asset, amount);
        return w.finish();
    }

    function testUnpackBalance(bytes calldata source) external pure returns (bytes32 asset, uint amount) {
        Cur memory cur = Decoders.open(source);
        return cur.unpackBalance();
    }

    function testUnpackBootstrap(
        bytes calldata source
    ) external pure returns (bytes32 asset, uint amount, uint budget) {
        Cur memory cur = Decoders.open(source);
        return cur.unpackBootstrap();
    }

    function testUnpackPosition(
        bytes calldata source
    ) external pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        Cur memory cur = Decoders.open(source);
        return cur.unpackPosition();
    }

    function testUnpackPositionValue(
        bytes calldata source
    ) external pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        Cur memory cur = Decoders.open(source);
        Position memory value = cur.unpackPositionValue();
        return (value.asset, value.amount, value.liability, value.debt, value.counterparty);
    }

    function testMemoryUnpackPosition(
        bytes calldata source
    ) external pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        bytes memory data = source;
        (uint abs, uint end) = Memory.bounds(data, Sizes.Position);
        if (end - abs != Sizes.Position) revert Blocks.InvalidBlock();
        return Memory.unpackPosition(abs);
    }

    function testMemoryUnpackPositionValue(bytes calldata source) external pure returns (Position memory) {
        bytes memory data = source;
        (uint abs, uint end) = Memory.bounds(data, Sizes.Position);
        if (end - abs != Sizes.Position) revert Blocks.InvalidBlock();
        return Memory.unpackPositionValue(abs);
    }

    function testMemoryUnpackBalance(
        bytes calldata source
    ) external pure returns (bytes32 asset, uint amount) {
        bytes memory data = source;
        (uint abs, uint end) = Memory.bounds(data, Sizes.Balance);
        if (end - abs != Sizes.Balance) revert Blocks.InvalidBlock();
        return Memory.unpackBalance(abs);
    }

    function testMemoryUnpackTwoBalances(
        bytes calldata source
    )
        external
        pure
        returns (bytes32 firstAsset, uint firstAmount, bytes32 secondAsset, uint secondAmount)
    {
        bytes memory data = source;
        (uint abs, uint end) = Memory.bounds(data, Sizes.Balance);
        if (end - abs != 2 * Sizes.Balance) revert Blocks.InvalidBlock();
        (firstAsset, firstAmount) = Memory.unpackBalance(abs);
        (secondAsset, secondAmount) = Memory.unpackBalance(abs + Sizes.Balance);
    }

    function testMemoryUnpackTransaction(
        bytes calldata source
    ) external pure returns (bytes32 from, bytes32 to, bytes32 asset, uint amount) {
        bytes memory data = source;
        (uint abs, uint end) = Memory.bounds(data, Sizes.Transaction);
        if (end - abs != Sizes.Transaction) revert Blocks.InvalidBlock();
        return Memory.unpackTransaction(abs);
    }

    function testUnpackHostAccountAsset(
        bytes calldata source
    ) external pure returns (uint host_, bytes32 account, bytes32 asset) {
        Cur memory cur = Decoders.open(source);
        return cur.unpackHostAccountAsset();
    }

    function testUnpackAccountAsset(
        bytes calldata source
    ) external pure returns (bytes32 account, bytes32 asset) {
        Cur memory cur = Decoders.open(source);
        return cur.unpackAccountAsset();
    }

    function testUnpackHostAsset(
        bytes calldata source
    ) external pure returns (uint host_, bytes32 asset) {
        Cur memory cur = Decoders.open(source);
        return cur.unpackHostAsset();
    }

    function testUnpackAccount(bytes calldata source) external pure returns (bytes32 account) {
        Cur memory cur = Decoders.open(source);
        return cur.unpackAccount();
    }

    function testToTxValue(bytes calldata source) external pure returns (bytes32 from_, bytes32 to_, bytes32 asset, uint amount) {
        Cur memory cur = Decoders.open(source);
        Tx memory value = cur.unpackTransactionValue();
        return (value.from, value.to, value.asset, value.amount);
    }

    function testOpen(bytes calldata source)
        external
        pure
        returns (uint sourceStart, uint pos, uint end, uint8 flags)
    {
        assembly ("memory-safe") {
            sourceStart := source.offset
        }
        Cur memory cur;
        cur = Decoders.open(source);
        pos = cur.state.position();
        end = cur.state.limit();
        flags = uint8(cur.state >> 64);
    }

    function testClose(bytes calldata source, uint amount) external pure returns (bool) {
        Cur memory cur = Decoders.open(source);
        cur.advance(amount);
        cur.close();
        return true;
    }

    function testPeek(bytes calldata source, uint i) external pure returns (bytes4 key, uint len) {
        Cur memory cur = Decoders.open(source);
        return cur.peek(Cursors.base(source) + i);
    }

    function testEnterAmount(bytes calldata source, uint spec)
        external
        pure
        returns (bytes32 asset, uint amount, uint i, uint end)
    {
        uint sourceOffset;
        assembly ("memory-safe") {
            sourceOffset := source.offset
        }
        Cur memory cur = Decoders.open(source);
        (, end) = cur.enter(spec);
        (asset, amount) = cur.unpackAmount();
        cur.expect(end);
        i = relativePosition(cur, source);
        end -= sourceOffset;
    }

    function testEnterWords(bytes calldata source, uint spec)
        external
        pure
        returns (bytes32 first, bytes32 second)
    {
        Cur memory cur = Decoders.open(source);
        (, uint end) = cur.enter(spec);
        first = cur.next32();
        second = cur.next32();
        cur.expect(end);
    }

    function testEnterAdvance(
        bytes calldata source,
        uint spec,
        uint advance
    ) external pure returns (uint abs, uint i, uint end) {
        uint offset;
        assembly ("memory-safe") {
            offset := source.offset
        }

        Cur memory cur = Decoders.open(source);
        (abs, end) = cur.enter(spec, advance);
        i = relativePosition(cur, source);
        return (abs - offset, i, end - offset);
    }

    function testEnterKeyAdvance(
        bytes calldata source,
        bytes4 key,
        uint advance
    ) external pure returns (uint body, uint i, uint end) {
        uint offset;
        assembly ("memory-safe") {
            offset := source.offset
        }

        Cur memory cur = Decoders.open(source);
        (body, end) = cur.enter(key, advance);
        i = relativePosition(cur, source);
        return (body - offset, i, end - offset);
    }

    function testAdvance(
        bytes calldata source,
        uint amount
    ) external pure returns (uint abs, uint i, bytes32 value) {
        uint offset;
        assembly ("memory-safe") {
            offset := source.offset
        }

        Cur memory cur = Decoders.open(source);
        abs = cur.absolute();
        cur.advance(amount);
        i = relativePosition(cur, source);
        value = Blocks.read32(abs);
        return (abs - offset, i, value);
    }

    function testTakeRaw(
        bytes calldata source,
        uint amount
    ) external pure returns (uint abs, uint i, bytes32 value) {
        uint offset;
        assembly ("memory-safe") {
            offset := source.offset
        }

        Cur memory cur = Decoders.open(source);
        abs = cur.take(amount);
        i = relativePosition(cur, source);
        value = Blocks.read32(abs);
        return (abs - offset, i, value);
    }

    function testEnterSized(bytes calldata source, uint spec)
        external
        pure
        returns (bytes1 a, bytes2 b, bytes4 c, bytes8 d, bytes16 e, bytes32 f)
    {
        Cur memory cur = Decoders.open(source);
        (, uint end) = cur.enter(spec);
        a = cur.next1();
        b = cur.next2();
        c = cur.next4();
        d = cur.next8();
        e = cur.next16();
        f = cur.next32();
        cur.expect(end);
    }

    function testPastCurrent(bytes calldata source) external pure returns (uint) {
        Cur memory cur = Decoders.open(source);
        return cur.past() - Cursors.base(source);
    }

    function testIsAtCurrent(bytes calldata source, bytes4 key) external pure returns (bool) {
        Cur memory cur = Decoders.open(source);
        return cur.isAt(key);
    }

    function testIsEmptyCurrent(bytes calldata source, bytes4 key) external pure returns (bool) {
        Cur memory cur = Decoders.open(source);
        return cur.isEmpty(key);
    }

    function testTryConsumeEmpty(
        bytes calldata source,
        bytes4 key
    ) external pure returns (bool empty, uint i, bool more) {
        Cur memory cur = Decoders.open(source);
        empty = cur.tryConsumeEmpty(key);
        i = relativePosition(cur, source);
        more = cur.more();
    }

    function testHasAt(bytes calldata source, uint i, bytes4 key) external pure returns (bool) {
        Cur memory cur = Decoders.open(source);
        return cur.hasAt(Cursors.base(source) + i, key);
    }

    function testRun(bytes calldata source, uint i, bytes4 key) external pure returns (uint count, uint position) {
        Cur memory cur = Decoders.open(source);
        uint offset = Cursors.base(source);
        cur.state = cur.state.seek(offset + i);
        count = cur.run(key);
        position = cur.state.position() - offset;
    }

    function testRunCount(bytes calldata source, uint i, bytes4 key) external pure returns (uint count) {
        (uint abs, uint limit) = Cursors.bounds(source);
        return Blocks.runCount(abs + i, limit, key);
    }

    function testRunExact(bytes calldata source, bytes4 key) external pure returns (uint count, uint end) {
        (uint abs, uint limit) = Cursors.bounds(source);
        (count, end) = Blocks.runExact(abs, limit, key);
        end -= abs;
    }

    function testSlice(bytes calldata source, uint from, uint to)
        external
        pure
        returns (uint offset, uint i, uint len)
    {
        uint sourceOffset;
        assembly ("memory-safe") {
            sourceOffset := source.offset
        }
        Cur memory cur = Decoders.open(source);
        Cur memory out = cur.slice(sourceOffset + from, sourceOffset + to);
        offset = out.state.position();
        i = 0;
        len = out.state.limit() - offset;
        return (offset - sourceOffset, i, len);
    }

    function testRaw(bytes calldata source) external pure returns (bytes calldata data) {
        Cur memory cur = Decoders.open(source);
        return cur.raw();
    }

    function testDecoderRaw(
        bytes calldata source,
        uint amount
    ) external pure returns (bytes calldata data) {
        Cur memory cur = Decoders.open(source);
        cur.advance(amount);
        return cur.raw();
    }

    function testCursorRaw(
        bytes calldata source,
        uint amount
    ) external pure returns (bytes calldata data) {
        uint cur = Cursors.wrap(source).advance(amount);
        return cur.raw();
    }

    function testRawSlice(bytes calldata source, uint from, uint to) external pure returns (bytes calldata data) {
        Cur memory cur = Decoders.open(source);
        uint offset = Cursors.base(source);
        return cur.raw(offset + from, offset + to);
    }

    function testSeek(bytes calldata source, uint end) external pure returns (uint i) {
        Cur memory cur = Decoders.open(source);
        uint offset = Cursors.base(source);
        cur.state = cur.state.seek(offset + end);
        i = cur.state.position() - offset;
    }

    function testSeekBackward(bytes calldata source, uint end) external pure returns (bool) {
        Cur memory cur = Decoders.open(source);
        uint target = Cursors.base(source) + end;
        cur.state = (cur.state & ~uint(type(uint32).max)) | (target + 1);
        cur.state.seek(target);
        return true;
    }

    function testExpectPosition(bytes calldata source, uint pos) external pure returns (uint i) {
        Cur memory cur = Decoders.open(source);
        uint offset = Cursors.base(source);
        uint target = offset + pos;
        cur.state = (cur.state & ~uint(type(uint32).max)) | target;
        cur.state.expect(target);
        i = cur.state.position() - offset;
    }

    function testExpectPositionMismatch(bytes calldata source, uint pos) external pure returns (bool) {
        Cur memory cur = Decoders.open(source);
        uint offset = Cursors.base(source);
        uint len = cur.state.limit() - offset;
        if (pos < len) {
            cur.state = (cur.state & ~uint(type(uint32).max)) | (offset + pos + 1);
        }
        cur.state.expect(offset + pos);
        return true;
    }

    function testList(bytes calldata source)
        external
        pure
        returns (uint itemsOffset, uint itemsI, uint itemsLen, uint inputI)
    {
        uint sourceOffset;
        assembly ("memory-safe") {
            sourceOffset := source.offset
        }
        Cur memory cur = Decoders.open(source);
        Cur memory items = cur.list();
        uint offset = items.state.position();
        itemsI = 0;
        itemsLen = items.state.limit() - offset;
        inputI = cur.state.position() - sourceOffset;
        return (offset - sourceOffset, itemsI, itemsLen, inputI);
    }

    function testListSpec(bytes calldata source, uint spec)
        external
        pure
        returns (uint itemsOffset, uint itemsI, uint itemsLen, uint inputI)
    {
        uint sourceOffset;
        assembly ("memory-safe") {
            sourceOffset := source.offset
        }
        Cur memory cur = Decoders.open(source);
        Cur memory items = cur.list(spec);
        uint offset = items.state.position();
        itemsI = 0;
        itemsLen = items.state.limit() - offset;
        inputI = cur.state.position() - sourceOffset;
        return (offset - sourceOffset, itemsI, itemsLen, inputI);
    }

    function testTakeBlock(bytes calldata source, bytes4 key)
        external
        pure
        returns (uint outOffset, uint outI, uint outLen, uint inputI)
    {
        uint sourceOffset;
        assembly ("memory-safe") {
            sourceOffset := source.offset
        }
        Cur memory cur = Decoders.open(source);
        Cur memory out = cur.takeBlock(key);
        uint offset = out.state.position();
        outI = 0;
        outLen = out.state.limit() - offset;
        inputI = cur.state.position() - sourceOffset;
        return (offset - sourceOffset, outI, outLen, inputI);
    }

    function testUnpackStep(
        bytes calldata source
    ) external pure returns (uint cmd, uint value, bytes calldata input, uint i) {
        Cur memory cur = Decoders.open(source);
        (cmd, value, input) = cur.unpackStep();
        i = relativePosition(cur, source);
    }

    function testUnpackContext(bytes calldata source)
        external
        pure
        returns (bytes32 account, bytes calldata state, bytes calldata input, uint i)
    {
        Cur memory cur = Decoders.open(source);
        (account, state, input) = cur.unpackContext();
        i = relativePosition(cur, source);
    }

    function testUnpackRecover(bytes calldata source)
        external
        pure
        returns (uint handler, uint resources, bytes32 key, bytes calldata witness, uint i)
    {
        Cur memory cur = Decoders.open(source);
        (handler, resources, key, witness) = cur.unpackRecover();
        i = relativePosition(cur, source);
    }

    function testUnpackRelay(bytes calldata source)
        external
        pure
        returns (uint portal, uint resources, bytes calldata steps, uint i)
    {
        Cur memory cur = Decoders.open(source);
        (bytes calldata input, bytes calldata continuation) = cur.unpackRelay();
        if (input.length >= 64) {
            assembly ("memory-safe") {
                portal := calldataload(input.offset)
                resources := calldataload(add(input.offset, 0x20))
            }
        }
        steps = continuation;
        i = relativePosition(cur, source);
    }

    function testUnpackRelayStreams(bytes calldata source)
        external
        pure
        returns (bytes calldata input, bytes calldata steps, uint i)
    {
        Cur memory cur = Decoders.open(source);
        (input, steps) = cur.unpackRelay();
        i = relativePosition(cur, source);
    }

    function testUnpackDispatch(bytes calldata source)
        external
        pure
        returns (uint portal, uint resources, bytes calldata payload, uint i)
    {
        Cur memory cur = Decoders.open(source);
        (portal, resources, payload) = cur.unpackDispatch();
        i = relativePosition(cur, source);
    }

}
