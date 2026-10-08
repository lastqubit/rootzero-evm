// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Execution, Executions} from "../execution/Execution.sol";

contract TestInputLogs {
    function logInput(bytes calldata input, uint id, uint mask) external returns (
        bytes32 beforeHash, bytes32 afterHash, uint beforeMemory, uint afterMemory, bytes memory output
    ) {
        Execution memory exec;
        uint descriptor = Executions.describe(0, 0, 0, 4 | (mask << 3));
        Executions.openInput(exec, descriptor, type(uint).max, input);
        Executions.outputBalance(exec, bytes32(uint(7)), 11);
        Executions.outputBalance(exec, bytes32(uint(13)), 17);
        beforeHash = keccak256(abi.encode(exec.account, exec.budget, exec.input, exec.state));
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        output = Executions.finish(exec, id, descriptor);
        assembly ("memory-safe") { afterMemory := mload(0x40) }
        afterHash = keccak256(abi.encode(exec.account, exec.budget, exec.input, exec.state));

    }
}
