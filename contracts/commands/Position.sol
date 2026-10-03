// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Execute} from "../codec/Execute.sol";
import {Position} from "../core/Types.sol";

/// @notice Check each POSITION against a paired POSITION_CONSTRAINTS block and preserve the position.
/// @dev Checks identifiers and inclusive quantity bounds, not counterparty authorization or backing.
abstract contract CheckPosition is CommandBase {
    using Executions for Execution;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("checkPosition", Specs.Position, Specs.PositionConstraints, Specs.Position, 0);
    }

    /// @notice Return the registered checkPosition command ID.
    function checkPositionId() internal view returns (uint) {
        return id;
    }

    /// @notice Require matching identifiers, at least the constrained amount, and at most the constrained debt.
    /// @param context Command context with one POSITION_CONSTRAINTS input per POSITION state block.
    /// @return Unchanged POSITION blocks.
    /// @return Zero native budget credit.
    function checkPosition(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, checkPositionOne);
    }

    function checkPositionOne(Execution memory exec) private pure {
        Position memory position = exec.unpackPositionValue();
        exec.expectPositionConstraints(position);
        exec.outputPosition(position);
    }
}

/// @notice Extends checkPosition with direct validation of memory-backed pipeline state.
abstract contract ExecuteCheckPosition is CheckPosition {
    /// @notice Validate positions in place without unpacking or copying their blocks.
    /// @param state POSITION block stream in memory.
    /// @param inputCur Cursor over exactly one calldata POSITION_CONSTRAINTS block per position.
    /// @param value Assigned native budget, returned unused.
    /// @return handled Always true.
    /// @return output The original state buffer, unchanged.
    /// @return credit Unused assigned native budget.
    function executeCheckPosition(
        bytes32,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal pure returns (bool handled, bytes memory output, uint credit) {
        Execute.checkPositions(state, inputCur);

        return (true, state, value);
    }
}
