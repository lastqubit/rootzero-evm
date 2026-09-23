// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Specs} from "../codec/Specs.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

contract TestOperation {

    function testOpenSources(
        bytes calldata context
    ) external pure returns (bool) {
        uint descriptor = Executions.describe(
            Specs.Balance,
            Specs.Amount,
            Specs.Empty,
            0
        );
        Execution memory exec;
        exec.openContext(descriptor, 0, context);
        return true;
    }
}
