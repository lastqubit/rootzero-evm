// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

// Example 3: Custom Command
//
// When no built-in module fits your use case, write your own command.
// A command is an abstract contract mixed into a host (not deployed standalone).
//
// Three things every custom command needs:
//   1. A descriptor for the state/input/output streams.
//   2. Metadata defined in the constructor to announce the command to the protocol.
//   3. The onlyCommand modifier on the entrypoint to enforce the trusted caller.

import {CommandBase, Execution, Executions, Specs} from "../contracts/Commands.sol";

using Executions for Execution;

abstract contract MyCommand is CommandBase {
    // The descriptor announces accepted input, state, output, and flags.
    uint private immutable descriptor;

    constructor() {
        // Announce this command to the rootzero protocol.
        // Args: name, state, input, output, flags.
        (, descriptor) = command("myCommand", Specs.Empty, Specs.Amount, Specs.Balance, 0);
    }

    function myCommand(
        bytes calldata context
    ) external onlyCommand returns (bytes memory, uint) {
        // onlyCommand enforces caller access. The runner opens and
        // closes the execution; runCommandOnce requires this callback to consume all input.
        return runCommandOnce(context, descriptor, myCommandOnce);
    }

    function myCommandOnce(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackAmount();

        // Apply your app logic here (e.g. debit the account), then append a BALANCE block.
        exec.outputBalance(asset, amount);
    }
}





