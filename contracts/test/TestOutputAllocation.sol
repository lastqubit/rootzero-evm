// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";
import {Specs} from "../codec/Specs.sol";
import {Buffers} from "../codec/Buffers.sol";

/// @dev Benchmark only: no-source executions with zero or one-block capacity hints.
contract TestOutputAllocation {
    using Executions for Execution;

    struct Measurement { uint gasUsed; uint memoryBytes; uint length; bytes32 digest; }

    function measure(bool seed, uint workload, uint count, uint repetitions)
        external view returns (Measurement memory result)
    {
        uint spec = workload == 0 ? Specs.Balance : workload == 1 ? Specs.Position : Specs.Bytes;
        uint descriptor = Executions.describe(0, 0, spec, 0);
        bytes memory payload = new bytes(workload == 2 ? 16 : workload == 3 ? 128 : 1024);
        bytes memory output;
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        uint beforeGas = gasleft();
        for (uint i; i < repetitions; ++i) {
            output = execute(seed, workload, count, descriptor, payload);
        }
        result.gasUsed = beforeGas - gasleft();
        uint memoryBytes;
        assembly ("memory-safe") { memoryBytes := sub(mload(0x40), beforeMemory) }
        result.memoryBytes = memoryBytes;
        result.length = output.length;
        result.digest = keccak256(output);
    }

    function execute(bool seed, uint workload, uint count, uint descriptor, bytes memory payload)
        private pure returns (bytes memory)
    {
        Execution memory exec;
        exec.writer = Buffers.cursor(seed ? uint32(descriptor >> 64) : 0);
        for (uint i; i < count; ++i) {
            if (workload == 0) exec.outputBalance(bytes32(uint(1)), i + 1);
            else if (workload == 1) exec.outputPosition(bytes32(uint(1)), i + 1, bytes32(uint(2)), i + 1, 0);
            else exec.outputBytes(payload);
        }
        return exec.finish();
    }
}
