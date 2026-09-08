// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Execution, Executions} from "../execution/Execution.sol";
import {PreviousExecutions} from "./PreviousExecutions.sol";
import {Specs} from "../codec/Specs.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Buffers} from "../codec/Buffers.sol";

contract TestExecutionOutputOptimization {
    struct Options { uint count; uint capacity; uint forgedLength; }
    struct Result { uint usedGas; uint footprint; bytes output; }
    function outputStep(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputStep(exec, 11, 22, ma);
            else PreviousExecutions.outputStep(exec, 11, 22, ma);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCall(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCall(exec, 11, 22, ma);
            else PreviousExecutions.outputCall(exec, 11, 22, ma);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputDispatch(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputDispatch(exec, 11, 22, ma);
            else PreviousExecutions.outputDispatch(exec, 11, 22, ma);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputRelay(bool optimized, bytes calldata a, bytes calldata b, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a; bytes memory mb = b;
        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputRelay(exec, ma, mb);
            else PreviousExecutions.outputRelay(exec, ma, mb);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputContext(bool optimized, bytes calldata a, bytes calldata b, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a; bytes memory mb = b;
        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputContext(exec, bytes32(uint(33)), ma, mb);
            else PreviousExecutions.outputContext(exec, bytes32(uint(33)), ma, mb);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputRecover(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputRecover(exec, 11, 22, bytes32(uint(33)), ma);
            else PreviousExecutions.outputRecover(exec, 11, 22, bytes32(uint(33)), ma);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputLabel(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputLabel(exec, bytes32(uint(33)), string(ma));
            else PreviousExecutions.outputLabel(exec, bytes32(uint(33)), string(ma));
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputSchema(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputSchema(exec, 11, string(ma), bytes32(uint(33)));
            else PreviousExecutions.outputSchema(exec, 11, string(ma), bytes32(uint(33)));
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCopyBlock(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCopyBlock(exec, Specs.Bytes, a);
            else PreviousExecutions.outputCopyBlock(exec, Specs.Bytes, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCopyList(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCopyList(exec, a);
            else PreviousExecutions.outputCopyList(exec, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCopyBytes(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCopyBytes(exec, a);
            else PreviousExecutions.outputCopyBytes(exec, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCopyString(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCopyString(exec, string(a));
            else PreviousExecutions.outputCopyString(exec, string(a));
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCopyStep(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCopyStep(exec, 11, 22, a);
            else PreviousExecutions.outputCopyStep(exec, 11, 22, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCopyCall(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCopyCall(exec, 11, 22, a);
            else PreviousExecutions.outputCopyCall(exec, 11, 22, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCopyDispatch(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCopyDispatch(exec, 11, 22, a);
            else PreviousExecutions.outputCopyDispatch(exec, 11, 22, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCopyRelay(bool optimized, bytes calldata a, bytes calldata b, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCopyRelay(exec, a, b);
            else PreviousExecutions.outputCopyRelay(exec, a, b);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCopyContext(bool optimized, bytes calldata a, bytes calldata b, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCopyContext(exec, bytes32(uint(33)), a, b);
            else PreviousExecutions.outputCopyContext(exec, bytes32(uint(33)), a, b);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCopyRecover(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        exec.writer = Buffers.cursor(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputEmpty(exec, bytes4(0x12345678));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCopyRecover(exec, 11, 22, bytes32(uint(33)), a);
            else PreviousExecutions.outputCopyRecover(exec, 11, 22, bytes32(uint(33)), a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
}
