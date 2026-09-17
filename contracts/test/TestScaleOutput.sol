// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";
import {Buffers} from "../codec/Buffers.sol";

contract TestScaleOutput {
    using Executions for Execution;

    function scale(uint cur, uint numerator, uint denominator) external pure returns (uint) {
        return Buffers.scale(cur, numerator, denominator);
    }

    function inspect(uint writer, uint numerator, uint denominator, uint mode)
        external pure returns (uint updated, uint allocated, uint footprint)
    {
        Execution memory exec;
        exec.writer = writer;
        if (mode == 1) exec.outputEmpty(bytes4(0x12345678));
        if (mode == 2) exec.reserve(0, 0);
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        exec.scaleOutput(numerator, denominator);
        assembly ("memory-safe") { footprint := sub(mload(0x40), beforeMemory) }
        return (exec.writer, exec.output.length, footprint);
    }

    function write(uint capacity, uint numerator, uint denominator, uint count, bool scaled)
        external view returns (bytes memory output, uint footprint, uint usedGas)
    {
        Execution memory exec;
        exec.writer = Buffers.cursor(capacity);
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        uint start = gasleft();
        if (scaled) exec.scaleOutput(numerator, denominator);
        for (uint i; i < count; i++) exec.outputBalance(bytes32(uint(1)), i + 1);
        output = exec.finish();
        usedGas = start - gasleft();
        assembly ("memory-safe") { footprint := sub(mload(0x40), beforeMemory) }
    }
}
