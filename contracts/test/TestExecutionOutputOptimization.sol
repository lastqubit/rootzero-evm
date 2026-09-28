// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {PreviousExecutions} from "./PreviousExecutions.sol";
import {Specs} from "../codec/Specs.sol";


contract TestExecutionOutputOptimization {
    struct Options { uint count; uint capacity; uint forgedLength; }
    struct Result { uint usedGas; uint footprint; bytes output; }
    function outputStep(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {
        bytes memory ma = a;
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
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
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
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
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
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
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
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
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
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
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
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
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
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
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { mstore(ma, optsLength) } }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputSchema(exec, 11, string(ma));
            else PreviousExecutions.outputSchema(exec, 11, string(ma));
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputBlockWrap(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint aCur;
        if (optimized) {
            aCur = Cursors.create(Cursors.base(a), Cursors.base(a) + a.length);
        }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputBlockWrap(exec, Specs.Bytes, aCur);
            else PreviousExecutions.outputCopyBlock(exec, Specs.Bytes, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputListWrap(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint aCur;
        if (optimized) {
            aCur = Cursors.create(Cursors.base(a), Cursors.base(a) + a.length);
        }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputListWrap(exec, aCur);
            else PreviousExecutions.outputCopyList(exec, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputBytesWrap(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint aCur;
        if (optimized) {
            aCur = Cursors.create(Cursors.base(a), Cursors.base(a) + a.length);
        }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputBytesWrap(exec, aCur);
            else PreviousExecutions.outputCopyBytes(exec, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputStringWrap(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint aCur;
        if (optimized) {
            aCur = Cursors.create(Cursors.base(a), Cursors.base(a) + a.length);
        }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputStringWrap(exec, aCur);
            else PreviousExecutions.outputCopyString(exec, string(a));
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputStepWrap(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint aCur;
        if (optimized) {
            aCur = Cursors.create(Cursors.base(a), Cursors.base(a) + a.length);
        }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputStepWrap(exec, 11, 22, aCur);
            else PreviousExecutions.outputCopyStep(exec, 11, 22, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputCallWrap(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint aCur;
        if (optimized) {
            aCur = Cursors.create(Cursors.base(a), Cursors.base(a) + a.length);
        }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputCallWrap(exec, 11, 22, aCur);
            else PreviousExecutions.outputCopyCall(exec, 11, 22, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputDispatchWrap(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint aCur;
        if (optimized) {
            aCur = Cursors.create(Cursors.base(a), Cursors.base(a) + a.length);
        }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputDispatchWrap(exec, 11, 22, aCur);
            else PreviousExecutions.outputCopyDispatch(exec, 11, 22, a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputRelayWrap(bool optimized, bytes calldata a, bytes calldata b, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint aCur;
        uint bCur;
        if (optimized) {
            aCur = Cursors.create(Cursors.base(a), Cursors.base(a) + a.length);
            bCur = Cursors.wrap(b);
        }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputRelayWrap(exec, aCur, bCur);
            else PreviousExecutions.outputCopyRelay(exec, a, b);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputContextWrap(bool optimized, bytes calldata a, bytes calldata b, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint aCur;
        uint bCur;
        if (optimized) {
            aCur = Cursors.create(Cursors.base(a), Cursors.base(a) + a.length);
            bCur = Cursors.wrap(b);
        }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputContextWrap(exec, bytes32(uint(33)), aCur, bCur);
            else PreviousExecutions.outputCopyContext(exec, bytes32(uint(33)), a, b);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
    function outputRecoverWrap(bool optimized, bytes calldata a, bytes calldata /* b */, Options calldata opts)
        external view returns(Result memory result) {

        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(opts.capacity);
        // A prefix ensures every tested write uses a nonzero buffer offset.
        Executions.outputBytes(exec, new bytes(0));
        uint optsLength = opts.forgedLength;
        if (optsLength != 0) { assembly ("memory-safe") { a.length := optsLength } }
        uint aCur;
        if (optimized) {
            aCur = Cursors.create(Cursors.base(a), Cursors.base(a) + a.length);
        }
        uint initialMemory; assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < opts.count; j++) {
            if (optimized) Executions.outputRecoverWrap(exec, 11, 22, bytes32(uint(33)), aCur);
            else PreviousExecutions.outputCopyRecover(exec, 11, 22, bytes32(uint(33)), a);
        }
        result.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(result, 32), sub(mload(0x40), initialMemory)) }
        result.output = Executions.finish(exec);
    }
}
