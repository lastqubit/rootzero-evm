// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Position} from "../core/Types.sol";
import {RepayHook} from "../core/Settlement.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";

using Executions for Execution;

/// @notice Repay each POSITION debt and emit the position with debt cleared.
abstract contract Repay is CommandBase, RepayHook, ActionAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("repay", Specs.Position, Specs.Empty, Specs.Position, 0);
        annotateAction(id, Actions.Repay);
    }

    /// @notice Fully repay each debt before emitting its remaining position.
    /// @param context POSITION state and empty input for the active account.
    /// @return Positions with zero debt and all other fields preserved.
    /// @return Zero native budget credit.
    function repay(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, descriptor);

        while (exec.more()) {
            Position memory position = exec.unpackPositionValue();
            repay(exec.account, position);
            position.debt = 0;
            exec.outputPosition(position);
        }
        
        return exec.close();
    }
}

