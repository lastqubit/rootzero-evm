// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {NodeAccess} from "../../core/Access.sol";
import {CommandBase, Execution, Executions, Flags, Specs} from "../Base.sol";

using Executions for Execution;

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
    /// Callbacks must preserve bounded cursors; finalization does not recheck them.
    /// Source pairing and parent boundaries remain the callback's responsibility.
    /// Emits one selected execution record after processing.
    /// @param id Registered endpoint ID used as the log prefix.
    /// @param descriptor Packed admin endpoint descriptor.
    /// @param context Exactly one CONTEXT block carrying account, state, and input.
    /// @param process Internal callback that consumes and processes one batch item.
    /// @return output Final encoded output block stream.
    /// @return credit Remaining native-value budget.
    function runAdmin(
        uint id,
        uint descriptor,
        bytes calldata context,
        function(Execution memory) internal process
    ) internal returns (bytes memory output, uint credit) {
        Execution memory exec = openAdminCommand(context, descriptor);

        while (exec.more()) {
            process(exec);
        }

        output = exec.finish(id, descriptor);
        credit = exec.drainBudget();
    }

    /// @notice Run an authorized admin context through a callback exactly once.
    /// @dev Authorizes even empty batches before logging or processing. The callback
    /// defines source shapes and must consume both bounded sources completely.
    /// Emits one selected execution record on close.
    /// @param id Registered endpoint ID used as the log prefix.
    /// @param descriptor Packed admin endpoint descriptor.
    /// @param context Exactly one CONTEXT block carrying account, state, and input.
    /// @param process Internal callback that processes the complete execution.
    /// @return output Final encoded output block stream.
    /// @return credit Remaining native-value budget.
    function runAdminOnce(
        uint id,
        uint descriptor,
        bytes calldata context,
        function(Execution memory) internal process
    ) internal returns (bytes memory output, uint credit) {
        Execution memory exec = openAdminCommand(context, descriptor);
        process(exec);
        return exec.close(id, descriptor);
    }
}
