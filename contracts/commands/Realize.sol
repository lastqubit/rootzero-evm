// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Position} from "../core/Types.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that fulfill an entire position.
/// @dev Intended for hosts without their own account balance ledger. Ledger hosts
/// use SettleHook instead; production hosts choose one position-fulfillment model.
abstract contract RealizeHook {
    /// @notice Fulfill a position in its existing asset and liability denominations.
    /// @dev Account format is trusted from the producer. Enforce operation-specific
    /// counterparty matching and authorization, and fulfill the entire
    /// obligation before returning counterparty zero. The host chooses its internal
    /// operation order and must preserve the asset and liability identifiers.
    /// Callers may validate the result with checkPosition in the same pipeline;
    /// a later failure reverts the hook's changes.
    /// @param account Account whose position is being realized.
    /// @param position Source position to fulfill completely.
    /// @return Complete realized position with unchanged asset and liability and zero counterparty.
    function realize(bytes32 account, Position memory position) internal virtual returns (Position memory);
}

/// @notice Realize each POSITION and return the hook's fulfilled result.
abstract contract Realize is CommandBase, RealizeHook {
    uint private constant LOGS = Logs.State | Logs.Output;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("realize", Specs.Position, Specs.Empty, Specs.Position, LOGS);
    }

    /// @notice Realize POSITION state blocks without caller-supplied outcome constraints.
    /// @dev Logs original POSITION state and fulfilled OUTPUT together after hooks.
    /// @param context Command context carrying POSITION state and empty input.
    /// @return POSITION blocks returned by the realization hook.
    /// @return Zero native budget credit.
    function realize(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, realizeOne);
    }

    function realizeOne(Execution memory exec) private {
        Position memory position = exec.unpackPositionValue();
        position = realize(exec.account, position);
        exec.outputPosition(position);
    }
}
