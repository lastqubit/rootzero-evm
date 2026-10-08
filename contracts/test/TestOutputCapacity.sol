// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs as PreviousLogs} from "./PreviousEventLogs.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Specs} from "../codec/Specs.sol";
import {Keys} from "../codec/Keys.sol";
import {Schemas} from "../codec/Schema.sol";
import {Logs} from "../codec/Logs.sol";

contract TestOutputCapacity {
    function catalog() external pure returns (bytes4, uint, string memory) {
        return (Keys.Output, Specs.Output, Schemas.Output);
    }
    function exact(bytes calldata input, bool extra) external returns (
        uint initialCapacity, uint finalCapacity, bool sameBuffer, uint initialFootprint, bytes memory output
    ) {
        Execution memory exec;
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        Executions.openInput(exec, Executions.describe(0, Specs.Balance, Specs.Balance), 0, input);
        assembly ("memory-safe") { initialFootprint := sub(mload(0x40), beforeMemory) }
        initialCapacity = uint32(exec.output >> 32);
        bytes memory initial = exec.buffer;
        while (Executions.more(exec)) {
            (bytes32 asset, uint amount, uint next) = Blocks.unpackBalance(exec.input);
            exec.input = next;
            Executions.outputBalance(exec, asset, amount);
        }
        if (extra) Executions.outputBalance(exec, bytes32(uint(99)), 123);
        finalCapacity = uint32(exec.output >> 32);
        bytes memory current = exec.buffer;
        assembly ("memory-safe") { sameBuffer := eq(initial, current) }
        output = Executions.finish(exec);
        PreviousLogs.memWrap(123, Keys.Output, output);
    }
}
