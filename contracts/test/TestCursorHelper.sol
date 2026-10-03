// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {LegacyMemory} from "./LegacyMemory.sol";

import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Position, Tx} from "../core/Types.sol";
import {Specs} from "../codec/Specs.sol";
import {Sizes} from "../Codec.sol";
import {Cursors} from "../utils/Cursors.sol";
import {OutOfBounds, InvalidBlock} from "../utils/Errors.sol";

using Cursors for uint;

contract TestCursorHelper {
    function relativePosition(uint cur, bytes calldata source) private pure returns (uint) {
        return cur.position() - Cursors.base(source);
    }

    function testCreate(uint abs, uint endAbs) external pure returns (uint cur) {
        return Cursors.create(abs, endAbs);
    }

    function testCursorBounds() external pure returns (uint abs, uint end) {
        return Cursors.create(10, 30).seek(15).bounds();
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
        uint cur = Cursors.create(offset, offset + len).seek(offset + i);
        (abs, cur) = cur.enter(amount);
        next = cur.position() - offset;
        more = cur.more();
    }

    /// @notice Exercise cursor resizing at an existing position.
    function testCursorResize(uint len, uint i, uint resized) external pure returns (uint next, uint capacity) {
        uint cur = Cursors.create(0, len).seek(i).resize(resized);
        next = cur.position();
        capacity = cur.limit();
    }

    /// @notice Decode through the absolute generic cursor for gas regression coverage.
    function absoluteCursorBytes(bytes calldata source) external pure returns (bytes32 digest, uint next) {
        uint cur = Cursors.wrap(source);
        uint a; uint b; uint c;
        (a, cur) = Blocks.unpackBytes(cur);
        (b, cur) = Blocks.unpackBytes(cur);
        (c, cur) = Blocks.unpackBytes(cur);
        digest = Blocks.hash(a) ^ Blocks.hash(b) ^ Blocks.hash(c);
        next = uint32(cur);
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
        (value, end) = LegacyBlocks.unpackBytes(abs);
        uint offset = uint32(cur >> 32);
        if (end < offset) revert OutOfBounds();
        uint nextPosition = end - offset;
        if (nextPosition < position || nextPosition > len) revert OutOfBounds();
        updated = (cur & ~uint(type(uint32).max)) | nextPosition;
    }

    function testWriteBalanceBlock(bytes32 asset, uint amount) external pure returns (bytes memory) {
        (bytes memory wBuffer, uint w) = Encoder.init(Specs.allocation(Specs.Balance, 1));
        (wBuffer, w) = Encoder.writeBalance(w, wBuffer, asset, amount);
        return Encoder.finish(w, wBuffer);
    }

    function testWriteCustodyBlock(
        uint host_,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory) {
        (bytes memory wBuffer, uint w) = Encoder.init(Specs.allocation(Specs.Custody, 1));
        (wBuffer, w) = Encoder.writeCustody(w, wBuffer, host_, asset, amount);
        return Encoder.finish(w, wBuffer);
    }

    function testWritePositionBlock(
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) external pure returns (bytes memory) {
        (bytes memory wBuffer, uint w) = Encoder.init(Specs.allocation(Specs.Position, 1));
        (wBuffer, w) = Encoder.writePosition(w, wBuffer, asset, amount, liability, debt, bytes32(0));
        return Encoder.finish(w, wBuffer);
    }

    function testWritePositionCounterparty(bytes32 counterparty) external pure returns (bytes memory) {
        return LegacyBlocks.createPosition(bytes32(0), 0, bytes32(0), 0, counterparty);
    }

    function testWritePositionStructBlock(
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) external pure returns (bytes memory) {
        (bytes memory wBuffer, uint w) = Encoder.init(Specs.allocation(Specs.Position, 1));
        (wBuffer, w) = Encoder.writePosition(w, wBuffer, asset, amount, liability, debt, bytes32(0));
        return Encoder.finish(w, wBuffer);
    }

    function testWriteTxBlock(
        bytes32 from_,
        bytes32 to_,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory) {
        (bytes memory wBuffer, uint w) = Encoder.init(Specs.allocation(Specs.Transaction, 1));
        (wBuffer, w) = Encoder.writeTransaction(w, wBuffer, from_, to_, asset, amount);
        return Encoder.finish(w, wBuffer);
    }

    function testWriteTxStructBlock(
        bytes32 from_,
        bytes32 to_,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory) {
        (bytes memory wBuffer, uint w) = Encoder.init(Specs.allocation(Specs.Transaction, 1));
        (wBuffer, w) = Encoder.writeTransaction(w, wBuffer, from_, to_, asset, amount);
        return Encoder.finish(w, wBuffer);
    }

    function testToDispatchBlock(uint portal, uint resources, bytes memory payload) external pure returns (bytes memory) {
        return LegacyBlocks.createDispatch(portal, resources, payload);
    }

    function testToBalanceBlock(bytes32 asset, uint amount) external pure returns (bytes memory) {
        return LegacyBlocks.createBalance(asset, amount);
    }

    function testToAssetAmountBlock(bytes32 asset, uint amount) external pure returns (bytes memory) {
        return LegacyBlocks.createAssetAmount(asset, amount);
    }

    function testToBootstrapBlock(bytes32 asset, uint amount, uint budget) external pure returns (bytes memory) {
        return LegacyBlocks.createBootstrap(asset, amount, budget);
    }

    function testToLabelBlock(bytes32 namespace, string memory name) external pure returns (bytes memory) {
        return LegacyBlocks.createLabel(namespace, name);
    }

    function testToActionBlock(uint value) external pure returns (bytes memory) {
        return LegacyBlocks.createAction(value);
    }

    function testToCounterpartyBlock(bytes32 account) external pure returns (bytes memory) {
        return LegacyBlocks.createCounterparty(account);
    }

    function testToSchemaBlock(uint spec, string memory body) external pure returns (bytes memory) {
        return LegacyBlocks.createSchema(spec, body);
    }

    function testToCustodyBlock(
        uint host_,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory) {
        return LegacyBlocks.createCustody(host_, asset, amount);
    }

    function testToPositionBlock(
        bytes32 asset,
        uint amount,
        bytes32 liability,
        uint debt
    ) external pure returns (bytes memory) {
        return LegacyBlocks.createPosition(asset, amount, liability, debt, bytes32(0));
    }

    function testToTransactionBlock(
        bytes32 from_,
        bytes32 to_,
        bytes32 asset,
        uint amount
    ) external pure returns (bytes memory) {
        return LegacyBlocks.createTransaction(from_, to_, asset, amount);
    }

    function testWriterFinishEmpty() external pure returns (bytes memory) {
        (bytes memory wBuffer, uint w) = Encoder.init(Specs.allocation(Specs.Balance, 1));
        return Encoder.finish(w, wBuffer);
    }

    function testWriterFinish(bytes32 asset, uint amount) external pure returns (bytes memory) {
        (bytes memory wBuffer, uint w) = Encoder.init(Specs.allocation(Specs.Balance, 2));
        (wBuffer, w) = Encoder.writeBalance(w, wBuffer, asset, amount);
        return Encoder.finish(w, wBuffer);
    }

    function testUnpackBalance(bytes calldata source) external pure returns (bytes32 asset, uint amount) {
        uint cur = Cursors.wrap(source);
        (asset, amount,) = Blocks.unpackBalance(cur);
    }

    function testUnpackBootstrap(
        bytes calldata source
    ) external pure returns (bytes32 asset, uint amount, uint budget) {
        uint cur = Cursors.wrap(source);
        (asset, amount, budget,) = Blocks.unpackBootstrap(cur);
    }

    function testUnpackPosition(
        bytes calldata source
    ) external pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        uint cur = Cursors.wrap(source);
        (asset, amount, liability, debt, counterparty,) = Blocks.unpackPosition(cur);
    }

    function testUnpackPositionValue(
        bytes calldata source
    ) external pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        uint cur = Cursors.wrap(source);
        Position memory value;
        (value.asset, value.amount, value.liability, value.debt, value.counterparty,) = Blocks.unpackPosition(cur);
        return (value.asset, value.amount, value.liability, value.debt, value.counterparty);
    }

    function testMemoryUnpackPosition(
        bytes calldata source
    ) external pure returns (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) {
        bytes memory data = source;
        (uint abs, uint end) = LegacyMemory.bounds(data, Sizes.Position);
        if (end - abs != Sizes.Position) revert InvalidBlock();
        return LegacyMemory.unpackPosition(abs);
    }

    function testMemoryUnpackPositionValue(bytes calldata source) external pure returns (Position memory) {
        bytes memory data = source;
        (uint abs, uint end) = LegacyMemory.bounds(data, Sizes.Position);
        if (end - abs != Sizes.Position) revert InvalidBlock();
        return LegacyMemory.unpackPositionValue(abs);
    }

    function testMemoryUnpackBalance(
        bytes calldata source
    ) external pure returns (bytes32 asset, uint amount) {
        bytes memory data = source;
        (uint abs, uint end) = LegacyMemory.bounds(data, Sizes.Balance);
        if (end - abs != Sizes.Balance) revert InvalidBlock();
        return LegacyMemory.unpackBalance(abs);
    }

    function testMemoryUnpackTwoBalances(
        bytes calldata source
    )
        external
        pure
        returns (bytes32 firstAsset, uint firstAmount, bytes32 secondAsset, uint secondAmount)
    {
        bytes memory data = source;
        (uint abs, uint end) = LegacyMemory.bounds(data, Sizes.Balance);
        if (end - abs != 2 * Sizes.Balance) revert InvalidBlock();
        (firstAsset, firstAmount) = LegacyMemory.unpackBalance(abs);
        (secondAsset, secondAmount) = LegacyMemory.unpackBalance(abs + Sizes.Balance);
    }

    function testMemoryUnpackTransaction(
        bytes calldata source
    ) external pure returns (bytes32 from, bytes32 to, bytes32 asset, uint amount) {
        bytes memory data = source;
        (uint abs, uint end) = LegacyMemory.bounds(data, Sizes.Transaction);
        if (end - abs != Sizes.Transaction) revert InvalidBlock();
        return LegacyMemory.unpackTransaction(abs);
    }

    function testUnpackHostAccountAsset(
        bytes calldata source
    ) external pure returns (uint host_, bytes32 account, bytes32 asset) {
        uint cur = Cursors.wrap(source);
        (host_, account, asset,) = Blocks.unpackHostAccountAsset(cur);
    }

    function testUnpackAccountAsset(
        bytes calldata source
    ) external pure returns (bytes32 account, bytes32 asset) {
        uint cur = Cursors.wrap(source);
        (account, asset,) = Blocks.unpackAccountAsset(cur);
    }

    function testUnpackHostAsset(
        bytes calldata source
    ) external pure returns (uint host_, bytes32 asset) {
        uint cur = Cursors.wrap(source);
        (host_, asset,) = Blocks.unpackHostAsset(cur);
    }

    function testUnpackAccount(bytes calldata source) external pure returns (bytes32 account) {
        uint cur = Cursors.wrap(source);
        (account,) = Blocks.unpackAccount(cur);
    }

    function testToTxValue(bytes calldata source) external pure returns (bytes32 from_, bytes32 to_, bytes32 asset, uint amount) {
        uint cur = Cursors.wrap(source);
        Tx memory value;
        (value.from, value.to, value.asset, value.amount,) = Blocks.unpackTransaction(cur);
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
        uint cur;
        cur = Cursors.wrap(source);
        pos = cur.position();
        end = cur.limit();
        flags = uint8(cur >> 64);
    }

    function testClose(bytes calldata source, uint amount) external pure returns (bool) {
        uint cur = Cursors.wrap(source);
        cur = Cursors.advance(cur, amount);
        cur.expect(cur.limit());
        return true;
    }

    function testPeek(bytes calldata source, uint i) external pure returns (bytes4 key, uint len) {
        uint cur = Cursors.wrap(source);
        return LegacyBlocks.peek(Cursors.base(source) + i, cur.limit());
    }

    function testEnterAssetAmount(bytes calldata source, uint spec)
        external
        pure
        returns (bytes32 asset, uint amount, uint i, uint end)
    {
        uint cur;
        (cur,) = Blocks.unpack(Cursors.wrap(source), spec);
        end = cur.limit();
        (asset, amount, cur) = Blocks.unpackAssetAmount(cur);
        cur.expect(end);
        i = relativePosition(cur, source);
        end -= Cursors.base(source);
    }

    function testEnterWords(bytes calldata source, uint spec)
        external
        pure
        returns (bytes32 first, bytes32 second)
    {
        (uint abs, uint payloadCur,) = Blocks.enter(Cursors.wrap(source), spec, 64);
        first = Blocks.read32(abs);
        second = Blocks.read32(abs + 32);
        payloadCur.expect(payloadCur.limit());
    }

    function testEnterAdvance(
        bytes calldata source,
        uint spec,
        uint advance
    ) external pure returns (uint abs, uint i, uint end) {
        uint payloadCur;
        (abs, payloadCur,) = Blocks.enter(Cursors.wrap(source), spec, advance);
        uint offset = Cursors.base(source);
        i = uint32(payloadCur) - offset;
        end = uint32(payloadCur >> 32) - offset;
        abs -= offset;
    }

    function testEnterKeyAdvance(
        bytes calldata source,
        bytes4 key,
        uint advance
    ) external pure returns (uint body, uint i, uint end) {
        uint payloadCur;
        (body, payloadCur,) = Blocks.enter(Cursors.wrap(source), key, advance);
        uint offset = Cursors.base(source);
        i = uint32(payloadCur) - offset;
        end = uint32(payloadCur >> 32) - offset;
        body -= offset;
    }

    function testAdvance(
        bytes calldata source,
        uint amount
    ) external pure returns (uint abs, uint i, bytes32 value) {
        uint offset;
        assembly ("memory-safe") {
            offset := source.offset
        }

        uint cur = Cursors.wrap(source);
        abs = uint32(cur);
        cur = Cursors.advance(cur, amount);
        i = relativePosition(cur, source);
        value = LegacyBlocks.read32(abs);
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

        uint cur = Cursors.wrap(source);
        (abs, cur) = cur.enter(amount);
        i = relativePosition(cur, source);
        value = LegacyBlocks.read32(abs);
        return (abs - offset, i, value);
    }

    function testEnterSized(bytes calldata source, uint spec)
        external
        pure
        returns (bytes1 a, bytes2 b, bytes4 c, bytes8 d, bytes16 e, bytes32 f)
    {
        (uint abs, uint payloadCur,) = Blocks.enter(Cursors.wrap(source), spec, 63);
        a = Blocks.read1(abs);
        b = Blocks.read2(abs + 1);
        c = Blocks.read4(abs + 3);
        d = Blocks.read8(abs + 7);
        e = Blocks.read16(abs + 15);
        f = Blocks.read32(abs + 31);
        payloadCur.expect(payloadCur.limit());
    }

    function testPastCurrent(bytes calldata source) external pure returns (uint) {
        uint cur = Cursors.wrap(source);
        (, uint len) = LegacyBlocks.peek(uint32(cur), cur.limit());
        return 8 + len;
    }

    function testIsAtCurrent(bytes calldata source, bytes4 key) external pure returns (bool) {
        uint cur = Cursors.wrap(source);
        return LegacyBlocks.hasAt(uint32(cur), cur.limit(), key);
    }

    function testHasAt(bytes calldata source, uint i, bytes4 key) external pure returns (bool) {
        uint cur = Cursors.wrap(source);
        return LegacyBlocks.hasAt(Cursors.base(source) + i, cur.limit(), key);
    }

    function testRun(bytes calldata source, uint i, bytes4 key) external pure returns (uint count, uint position) {
        uint cur = Cursors.wrap(source);
        uint offset = Cursors.base(source);
        cur = cur.seek(offset + i);
        (count,) = LegacyBlocks.run(uint32(cur), cur.limit(), key);
        position = cur.position() - offset;
    }

    function testRunCount(bytes calldata source, uint i, bytes4 key) external pure returns (uint count) {
        (uint abs, uint limit) = Cursors.bounds(source);
        return LegacyBlocks.runCount(abs + i, limit, key);
    }

    function testRunExact(bytes calldata source, bytes4 key) external pure returns (uint count, uint end) {
        (uint abs, uint limit) = Cursors.bounds(source);
        (count, end) = LegacyBlocks.runExact(abs, limit, key);
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
        uint cur = Cursors.wrap(source);
        uint out = cur.slice(sourceOffset + from, sourceOffset + to);
        offset = out.position();
        i = 0;
        len = out.limit() - offset;
        return (offset - sourceOffset, i, len);
    }

    function testRaw(bytes calldata source) external pure returns (bytes calldata data) {
        uint cur = Cursors.wrap(source);
        return cur.toBytes();
    }

    function testDecoderRaw(
        bytes calldata source,
        uint amount
    ) external pure returns (bytes calldata data) {
        uint cur = Cursors.wrap(source);
        cur = Cursors.advance(cur, amount);
        return cur.toBytes();
    }

    function testCursorRaw(
        bytes calldata source,
        uint amount
    ) external pure returns (bytes calldata data) {
        uint cur = Cursors.wrap(source).advance(amount);
        return cur.toBytes();
    }

    function testRawSlice(bytes calldata source, uint from, uint to) external pure returns (bytes calldata data) {
        uint cur = Cursors.wrap(source);
        uint offset = Cursors.base(source);
        return cur.slice(offset + from, offset + to).toBytes();
    }

    function testSeek(bytes calldata source, uint end) external pure returns (uint i) {
        uint cur = Cursors.wrap(source);
        uint offset = Cursors.base(source);
        cur = cur.seek(offset + end);
        i = cur.position() - offset;
    }

    function testSeekBackward(bytes calldata source, uint end) external pure returns (bool) {
        uint cur = Cursors.wrap(source);
        uint target = Cursors.base(source) + end;
        cur = (cur & ~uint(type(uint32).max)) | (target + 1);
        cur.seek(target);
        return true;
    }

    function testExpectPosition(bytes calldata source, uint pos) external pure returns (uint i) {
        uint cur = Cursors.wrap(source);
        uint offset = Cursors.base(source);
        uint target = offset + pos;
        cur = (cur & ~uint(type(uint32).max)) | target;
        cur.expect(target);
        i = cur.position() - offset;
    }

    function testExpectPositionMismatch(bytes calldata source, uint pos) external pure returns (bool) {
        uint cur = Cursors.wrap(source);
        uint offset = Cursors.base(source);
        uint len = cur.limit() - offset;
        if (pos < len) {
            cur = (cur & ~uint(type(uint32).max)) | (offset + pos + 1);
        }
        cur.expect(offset + pos);
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
        uint cur = Cursors.wrap(source);
        (uint items, uint nextCur) = Blocks.unpackList(cur);
        cur = nextCur;
        uint offset = items.position();
        itemsI = 0;
        itemsLen = items.limit() - offset;
        inputI = cur.position() - sourceOffset;
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
        uint cur = Cursors.wrap(source);
        (uint items, uint nextCur) = Blocks.unpack(cur, spec);
        cur = nextCur;
        uint offset = items.position();
        itemsI = 0;
        itemsLen = items.limit() - offset;
        inputI = cur.position() - sourceOffset;
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
        uint cur = Cursors.wrap(source);
        (uint out, uint nextCur) = Blocks.take(cur, key);
        cur = nextCur;
        uint offset = out.position();
        outI = 0;
        outLen = out.limit() - offset;
        inputI = cur.position() - sourceOffset;
        return (offset - sourceOffset, outI, outLen, inputI);
    }

    function testUnpackStep(
        bytes calldata source
    ) external pure returns (uint cmd, uint value, bytes calldata input, uint i) {
        uint cur = Cursors.wrap(source);
        uint inputCur;
        (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
        input = Blocks.toBytes(inputCur);
        i = relativePosition(cur, source);
    }

    function testUnpackContext(bytes calldata source)
        external
        pure
        returns (bytes32 account, bytes calldata state, bytes calldata input, uint i)
    {
        uint cur = Cursors.wrap(source);
        uint stateCur;
        uint inputCur;
        (account, stateCur, inputCur, cur) = Blocks.unpackContext(cur);
        state = Blocks.toBytes(stateCur);
        input = Blocks.toBytes(inputCur);
        i = relativePosition(cur, source);
    }

    function testUnpackRecover(bytes calldata source)
        external
        pure
        returns (uint handler, uint value, bytes32 key, bytes calldata witness, uint i)
    {
        uint cur = Cursors.wrap(source);
        uint witnessCur;
        (handler, value, key, witnessCur, cur) = Blocks.unpackRecover(cur);
        witness = Blocks.toBytes(witnessCur);
        i = relativePosition(cur, source);
    }

    function testUnpackRelay(bytes calldata source)
        external
        pure
        returns (uint portal, uint resources, bytes calldata steps, uint i)
    {
        (uint inputCur, uint stepsCur, uint nextCur) = Blocks.unpackRelay(Cursors.wrap(source));
        if (Blocks.length(inputCur) >= 64) {
            portal = uint(Blocks.read32(uint32(inputCur)));
            resources = uint(Blocks.read32(uint32(inputCur) + 32));
        }
        steps = Blocks.toBytes(stepsCur);
        i = relativePosition(nextCur, source);
    }

    function testUnpackRelayStreams(bytes calldata source)
        external
        pure
        returns (bytes calldata input, bytes calldata steps, uint i)
    {
        uint cur = Cursors.wrap(source);
        uint inputCur;
        uint stepsCur;
        (inputCur, stepsCur, cur) = Blocks.unpackRelay(cur);
        input = Blocks.toBytes(inputCur);
        steps = Blocks.toBytes(stepsCur);
        i = relativePosition(cur, source);
    }

    function testUnpackDispatch(bytes calldata source)
        external
        pure
        returns (uint portal, uint resources, bytes calldata payload, uint i)
    {
        uint cur = Cursors.wrap(source);
        uint payloadCur;
        (portal, resources, payloadCur, cur) = Blocks.unpackDispatch(cur);
        payload = Blocks.toBytes(payloadCur);
        i = relativePosition(cur, source);
    }

}
