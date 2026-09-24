// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Position} from "../core/Types.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that fulfill an entire position.
/// @dev Intended for hosts without their own account balance ledger. Ledger hosts
/// use SettleHook instead; production hosts choose one position-fulfillment model.
abstract contract RealizeHook {
    /// @notice Fulfill a position in its existing asset and liability denominations.
    /// @dev Validate and authorize the source counterparty and fulfill the entire
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
abstract contract Realize is CommandBase, RealizeHook, ActionAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("realize", Specs.Position, Specs.Empty, Specs.Position, 0);
        annotateAction(id, Actions.Realize);
    }

    /// @notice Realize POSITION state blocks without caller-supplied outcome constraints.
    /// @param context Command context carrying POSITION state and empty input.
    /// @return POSITION blocks returned by the realization hook.
    /// @return Zero native budget credit.
    function realize(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, realizeOne);
    }

    function realizeOne(Execution memory exec) private {
        Position memory position = exec.unpackPositionValue();
        position = realize(exec.account, position);
        exec.outputPosition(position);
    }
}
