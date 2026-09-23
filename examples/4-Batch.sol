// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

// Example 4: Batch Processing
//
// Inputs can contain multiple blocks of the same type.
// This example uses the runner to process all AMOUNT blocks in input
// and produce a matching BALANCE block for each one.
//
// Execution owns the response buffer and grows it through output helpers.

import {CommandBase, Execution, Executions, Specs} from "../contracts/Commands.sol";

using Executions for Execution;

abstract contract MyCommand is CommandBase {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("myCommand", Specs.Empty, Specs.Amount, Specs.Balance, 0);
    }

    function myCommand(
        bytes calldata context
    ) external onlyCommand returns (bytes memory, uint) {
        // runCommand owns opening, batch iteration, and finalization. Empty input is valid.
        return runCommand(context, descriptor, myCommandOne);
    }

    function myCommandOne(Execution memory exec) private pure {
        // Unpack one AMOUNT and append its matching BALANCE.
        (bytes32 asset, uint amount) = exec.unpackAmount();
        exec.outputBalance(asset, amount);
    }
}






