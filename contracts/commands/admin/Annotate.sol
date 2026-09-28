// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../../codec/Blocks.sol";
import {AdminBase, Execution, Executions, Flags, Specs} from "./Base.sol";
using Executions for Execution;
using Blocks for uint;

/// @title Annotate
/// @notice Admin command that attaches encoded annotation block streams to entities.
/// Each ANNOTATION block in the input emits one `Annotation` event. Only callable
/// by the admin account.
abstract contract Annotate is AdminBase {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("annotate", Specs.Empty, Specs.Annotation, Specs.Empty, Flags.Admin);
    }

    /// @notice Publish each ANNOTATION block in the admin input.
    /// @param context Admin command context carrying the ANNOTATION input stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function annotate(
        bytes calldata context
    ) external returns (bytes memory, uint) {
        return runAdminCommand(context, descriptor, annotateOne);
    }

    function annotateOne(Execution memory exec) private {
        (uint entity, uint dataCur) = exec.unpackAnnotation();
        emit Annotation(entity, dataCur.toBytes());
    }
}
