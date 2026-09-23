// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

// Example 8: Budget Credit
//
// Commands return a trusted native value that replenishes the caller's shared
// execution budget. The credit may be derived from command-specific sources;
// it is not constrained to the command's call-value budget.

import {Host} from "../contracts/Core.sol";
import {CommandBase, Execution, Executions, Specs} from "../contracts/Commands.sol";

using Executions for Execution;

abstract contract MyCommand is CommandBase {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("myCommand", Specs.Empty, Specs.Node, Specs.Empty, 0);
    }

    function myCommand(
        bytes calldata context
    ) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, myCommandOne);
    }

    function myCommandOne(Execution memory exec) private pure {
        uint amount = exec.unpackNode();
        exec.addToBudget(amount);
    }
}

// Concrete host so the example can be deployed and called in tests.
contract ExampleHost is Host, MyCommand {
    constructor(uint rootzero) Host(rootzero) {}
}
