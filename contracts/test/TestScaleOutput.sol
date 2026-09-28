// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder} from "../codec/Encoder.sol";

import {Execution, Executions} from "../execution/Execution.sol";
import {LegacyBuffers} from "./LegacyBuffers.sol";

contract TestScaleOutput {
    using Executions for Execution;

    function scale(uint cur, uint numerator, uint denominator) external pure returns (uint) {
        return LegacyBuffers.scale(cur, numerator, denominator);
    }

    function write(uint capacity, uint numerator, uint denominator, uint count, bool scaled)
        external view returns (bytes memory output, uint footprint, uint usedGas)
    {
        Execution memory exec;
        exec.output = LegacyBuffers.cursor(capacity);
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        uint start = gasleft();
        if (scaled) exec.output = LegacyBuffers.scale(exec.output, numerator, denominator);
        // Legacy scale experiment explicitly precedes encoder initialization.
        (exec.buffer, exec.output) = Encoder.init(uint32(exec.output >> 32));
        for (uint i; i < count; i++) exec.outputBalance(bytes32(uint(1)), i + 1);
        output = exec.finish();
        usedGas = start - gasleft();
        assembly ("memory-safe") { footprint := sub(mload(0x40), beforeMemory) }
    }
}
