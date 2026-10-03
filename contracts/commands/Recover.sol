// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {Execution, Executions, CommandBase, Flags, Specs} from "./Base.sol";

using Executions for Execution;
using Blocks for uint;

/// @notice Hook implemented by hosts that recover previously unresolved payloads.
abstract contract RecoverPayableHook {
    /// @notice Override to recover a witness through `handler`.
    /// @param handler Port that should attempt recovery.
    /// @param value Full-width native value assigned to the handler call.
    /// Debit it from funds with useValue or rawCall; do not truncate it to a resource lane.
    /// @param key Recovery lookup key.
    /// @param witnessCur Bounded calldata cursor over the witness payload used for recovery.
    /// @param funds Shared execution containing the source value budget.
    function recover(
        uint handler,
        uint value,
        bytes32 key,
        uint witnessCur,
        Execution memory funds
    ) internal virtual;
}

/// @title RecoverPayable
/// @notice Command that forwards recover input blocks to a virtual hook.
/// Recovery is witness-driven: the command account pays and receives leftover
/// value posting, but the recovered subject is defined by each witness.
/// Produces no output state.
abstract contract RecoverPayable is CommandBase, RecoverPayableHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("recoverPayable", Specs.Empty, Specs.Recover, Specs.Empty, Flags.Funded);
    }

    /// @notice Recover each recover block in the command input.
    /// @param context Command context carrying the RECOVER input stream.
    /// @return Empty output state.
    /// @return Native value to add to the caller's budget.
    function recoverPayable(bytes calldata context) external payable onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, recoverPayableOne);
    }

    function recoverPayableOne(Execution memory exec) private {
        (uint handler, uint value, bytes32 key, uint witnessCur) = exec.unpackRecover();
        recover(handler, value, key, witnessCur, exec);
    }
}
