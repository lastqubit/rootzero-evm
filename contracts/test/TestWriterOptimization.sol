// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Writer, Writers} from "../codec/Writers.sol";
import {PreviousWriters} from "./PreviousWriters.sol";
import {Specs} from "../codec/Specs.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Buffers} from "../codec/Buffers.sol";

contract TestWriterOptimization {
    struct Options { uint count; uint capacity; uint forgedLength; }
    struct Result { uint usedGas; uint footprint; bytes output; }
    function appendStep(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.appendStep(writer, 11, 22, ma);
            else PreviousWriters.appendStep(writer, 11, 22, ma);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function appendCall(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.appendCall(writer, 11, 22, ma);
            else PreviousWriters.appendCall(writer, 11, 22, ma);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function appendDispatch(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.appendDispatch(writer, 11, 22, ma);
            else PreviousWriters.appendDispatch(writer, 11, 22, ma);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function appendRelay(bool optimized, bytes calldata a, bytes calldata b, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a; bytes memory mb = b;
        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.appendRelay(writer, ma, mb);
            else PreviousWriters.appendRelay(writer, ma, mb);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function appendContext(bool optimized, bytes calldata a, bytes calldata b, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a; bytes memory mb = b;
        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.appendContext(writer, bytes32(uint(33)), ma, mb);
            else PreviousWriters.appendContext(writer, bytes32(uint(33)), ma, mb);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function appendRecover(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.appendRecover(writer, 11, 22, bytes32(uint(33)), ma);
            else PreviousWriters.appendRecover(writer, 11, 22, bytes32(uint(33)), ma);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function appendLabel(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.appendLabel(writer, bytes32(uint(33)), string(ma));
            else PreviousWriters.appendLabel(writer, bytes32(uint(33)), string(ma));
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function appendSchema(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.appendSchema(writer, 11, string(ma), bytes32(uint(33)));
            else PreviousWriters.appendSchema(writer, 11, string(ma), bytes32(uint(33)));
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function copyBlock(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.copyBlock(writer, Specs.Bytes, a);
            else PreviousWriters.copyBlock(writer, Specs.Bytes, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function copyList(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.copyList(writer, a);
            else PreviousWriters.copyList(writer, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function copyBytes(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.copyBytes(writer, a);
            else PreviousWriters.copyBytes(writer, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function copyString(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.copyString(writer, string(a));
            else PreviousWriters.copyString(writer, string(a));
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function copyStep(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.copyStep(writer, 11, 22, a);
            else PreviousWriters.copyStep(writer, 11, 22, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function copyCall(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.copyCall(writer, 11, 22, a);
            else PreviousWriters.copyCall(writer, 11, 22, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function copyDispatch(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.copyDispatch(writer, 11, 22, a);
            else PreviousWriters.copyDispatch(writer, 11, 22, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function copyRelay(bool optimized, bytes calldata a, bytes calldata b, Options calldata opts)
        external view returns(Result memory result) {

        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.copyRelay(writer, a, b);
            else PreviousWriters.copyRelay(writer, a, b);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function copyContext(bool optimized, bytes calldata a, bytes calldata b, Options calldata opts)
        external view returns(Result memory result) {

        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.copyContext(writer, bytes32(uint(33)), a, b);
            else PreviousWriters.copyContext(writer, bytes32(uint(33)), a, b);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function copyRecover(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.copyRecover(writer, 11, 22, bytes32(uint(33)), a);
            else PreviousWriters.copyRecover(writer, 11, 22, bytes32(uint(33)), a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
    function appendBlock(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        bytes memory ma = a;
        Writer memory writer;
        writer.cur = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Writers.appendEmpty(writer, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Writers.appendBlock(writer, Specs.Bytes, ma);
            else PreviousWriters.appendBlock(writer, Specs.Bytes, ma);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Writers.finish(writer);
    }
}
