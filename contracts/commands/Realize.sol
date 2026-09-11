// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Position} from "../core/Types.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that fulfill an entire position.
abstract contract RealizeHook {
    /// @notice Fulfill a position in its existing asset and liability denominations.
    /// @dev Validate and authorize the source counterparty and fulfill the entire
    /// obligation before returning counterparty zero. The host chooses its internal
    /// operation order and must preserve the asset and liability identifiers.
    /// The command validates only the returned quantity limits;
    /// any failure reverts the hook's changes.
    /// @param account Account whose position is being realized.
    /// @param position Source position to fulfill completely.
    /// @return Complete realized position with unchanged asset and liability and zero counterparty.
    function realize(bytes32 account, Position memory position) internal virtual returns (Position memory);
}

/// @notice Realize each POSITION and enforce its paired LIMITS on the result.
abstract contract Realize is CommandBase, RealizeHook, ActionAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("realize", Specs.Position, Specs.Limits, Specs.Position, 0);
        annotateAction(id, Actions.Realize);
    }

    /// @notice Realize POSITION state blocks within their paired quantity limits.
    /// @param context Command context carrying POSITION state and one LIMITS input per position.
    /// @return POSITION blocks returned by the realization hook.
    /// @return Zero native budget credit.
    function realize(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, descriptor);

        while (exec.more()) {
            Position memory position = exec.unpackPositionValue();
            position = realize(exec.account, position);
            exec.requireLimits(position.amount, position.debt);
            exec.outputPosition(position);
        }

        return exec.close();
    }
}
