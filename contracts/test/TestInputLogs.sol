// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Execution, Executions} from "../execution/Execution.sol";
import {Encoder} from "../codec/Encoder.sol";

contract TestInputLogs {
    function logInput(bytes calldata input, uint id, uint mask) external returns (
        bytes32 beforeHash, bytes32 afterHash, uint beforeMemory, uint afterMemory, bytes memory output
    ) {
        Execution memory exec;
        uint descriptor = Executions.describe(mask & 1, (mask >> 1) & 1, (mask >> 2) & 1);
        Executions.openInput(exec, descriptor, type(uint).max, input);
        Executions.outputBalance(exec, bytes32(uint(7)), 11);
        beforeHash = keccak256(abi.encode(exec));
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        Executions.logInput(exec, id, descriptor);
        assembly ("memory-safe") { afterMemory := mload(0x40) }
        afterHash = keccak256(abi.encode(exec));
        // The next allocation and write must remain safe after temporary logging.
        Executions.outputBalance(exec, bytes32(uint(13)), 17);
        output = Encoder.finish(exec.output, exec.buffer);
    }
}
