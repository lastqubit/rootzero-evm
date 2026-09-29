// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Execution, Executions, Flags, Specs} from "../Base.sol";
import {NodeAccess} from "../../core/Access.sol";

/// @title AdminBase
/// @notice Shared base for admin commands.
abstract contract AdminBase is NodeAccess, CommandBase {
    /// @notice Open and authorize one admin command context.
    function openAdminCommand(
        bytes calldata context,
        uint descriptor
    ) internal view returns (Execution memory exec) {
        exec = openCommand(context, descriptor);
        enforceAdmin(exec.account, msg.sender);
    }

    /// @notice Run an authorized admin context through a callback for each batch item.
    /// @dev Opens exactly one CONTEXT using `msg.value` as its initial budget and
    /// enforces admin access before processing, including for empty batches.
    /// The callback shares the execution and must advance state or input on each
    /// iteration until both sources are consumed. No progress guard is enforced.
    /// Source pairing and parent boundaries remain the callback's responsibility.
    /// @param context Exactly one CONTEXT block carrying account, state, and input.
    /// @param descriptor Packed admin endpoint descriptor.
    /// @param process Internal callback that consumes and processes one batch item.
    /// @return output Final encoded output block stream.
    /// @return credit Remaining native-value budget.
    function runAdmin(
        bytes calldata context,
        uint descriptor,
        function(Execution memory) internal process
    ) internal returns (bytes memory output, uint credit) {
        Execution memory exec = openAdminCommand(context, descriptor);

        while (Executions.more(exec)) {
            process(exec);
        }

        return Executions.close(exec);
    }
}
