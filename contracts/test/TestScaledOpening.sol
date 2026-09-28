// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Execution, Executions} from "../execution/Execution.sol";
import {Encoder} from "../codec/Encoder.sol";
import {PreviousScaledOpening} from "./PreviousScaledOpening.sol";
contract TestScaledOpening {
    function inspect(bytes calldata source, uint descriptor, uint numerator, uint denominator, bool contextMode)
        external pure returns (uint capacity, uint footprint, bytes32 account, uint budget, uint inputCur, uint stateCur, uint bufferSize)
    {
        Execution memory exec;
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        if (contextMode) Executions.openContext(exec, descriptor, 99, source, numerator, denominator);
        else Executions.openInput(exec, descriptor, 99, source, numerator, denominator);
        assembly ("memory-safe") { footprint := sub(mload(0x40), beforeMemory) }
        return (uint32(exec.output >> 32), footprint, exec.account, exec.budget, exec.input, exec.state, exec.buffer.length);
    }

    function write(bytes calldata source, uint descriptor, uint numerator, uint denominator, bool contextMode, uint count)
        external pure returns (bytes memory output)
    {
        Execution memory exec;
        if (contextMode) Executions.openContext(exec, descriptor, 99, source, numerator, denominator);
        else Executions.openInput(exec, descriptor, 99, source, numerator, denominator);
        for (uint i; i < count; ++i) Executions.outputBalance(exec, bytes32(uint(1)), i + 1);
        return Encoder.finish(exec.output, exec.buffer);
    }
}
contract ScaledOpeningPrevious {
    function measure(bytes calldata source, uint descriptor, bool contextMode)
        external view returns (uint used, uint footprint, bytes32 account, uint budget, uint inputCur, uint stateCur, uint outputCur, uint bufferSize)
    {
        Execution memory exec;
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        uint beforeGas = gasleft();
        if (contextMode) PreviousScaledOpening.openContext(exec, descriptor, 99, source);
        else PreviousScaledOpening.openInput(exec, descriptor, 99, source);
        used = beforeGas - gasleft();
        assembly ("memory-safe") { footprint := sub(mload(0x40), beforeMemory) }
        return (used, footprint, exec.account, exec.budget, exec.input, exec.state, exec.output, exec.buffer.length);
    }
}
contract ScaledOpeningCurrent {
    function measure(bytes calldata source, uint descriptor, bool contextMode)
        external view returns (uint used, uint footprint, bytes32 account, uint budget, uint inputCur, uint stateCur, uint outputCur, uint bufferSize)
    {
        Execution memory exec;
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        uint beforeGas = gasleft();
        if (contextMode) Executions.openContext(exec, descriptor, 99, source);
        else Executions.openInput(exec, descriptor, 99, source);
        used = beforeGas - gasleft();
        assembly ("memory-safe") { footprint := sub(mload(0x40), beforeMemory) }
        return (used, footprint, exec.account, exec.budget, exec.input, exec.state, exec.output, exec.buffer.length);
    }
}
