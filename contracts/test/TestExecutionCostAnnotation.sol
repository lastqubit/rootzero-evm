// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, ExecutionCost, Blocks, Specs} from "../Commands.sol";
import {ExecutionCost as CoreExecutionCost, Runtime} from "../Core.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestExecutionCostAnnotation is CommandBase, ExecutionCost {
    uint public immutable commandId;

    constructor(uint base, uint batch) Runtime(0) {
        (commandId,) = command("costed", Specs.Balance, Specs.Empty, Specs.Balance, 0);
        executionCost(commandId, base, batch);
    }

    function publish(uint base, uint batch) external { executionCost(commandId, base, batch); }
    function encode(uint base, uint batch) external pure returns (bytes memory) {
        return Blocks.createExecutionCost(base, batch);
    }
    function catalog() external pure returns (uint spec, string memory body) {
        return (Specs.ExecutionCost, Schemas.ExecutionCost);
    }
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
}

contract TestCoreExecutionCostImport is CoreExecutionCost {}
