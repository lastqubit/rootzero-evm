// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";

contract TestCommandContext {
    function inspect(bytes calldata context, uint descriptor, uint budget)
        external pure returns (Execution memory exec, uint offset)
    {
        assembly ("memory-safe") { offset := context.offset }
        Executions.openContext(exec, descriptor, budget, context);
    }
}
