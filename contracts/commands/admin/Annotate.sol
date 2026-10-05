// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AdminBase, Execution, Executions, Flags, Specs} from "./Base.sol";
import {Codes} from "../../utils/Codes.sol";
using Executions for Execution;

/// @title Annotate
/// @notice Admin command that attaches encoded annotation block streams to entities.
/// Logs the complete ANNOTATION input batch under the publishing host scope.
/// Only callable by the admin account.
abstract contract Annotate is AdminBase {
    uint private constant INPUT = Specs.Annotation | Codes.HostAnnotate;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("annotate", Specs.Empty, INPUT, Specs.Empty, Flags.Admin);
    }

    /// @notice Publish each ANNOTATION block in the admin input.
    /// @param context Admin command context carrying the ANNOTATION input stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function annotate(
        bytes calldata context
    ) external returns (bytes memory, uint) {
        return runAdminOnce(id, descriptor, context, annotateOnce);
    }

    function annotateOnce(Execution memory exec) private pure {
        // Validate each envelope; the runner logs the original batch once.
        exec.takeAnnotations();
    }
}
