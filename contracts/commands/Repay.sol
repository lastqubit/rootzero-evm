// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {RepayHook} from "../core/Settlement.sol";
import {Position} from "../core/Types.sol";

using Executions for Execution;

/// @notice Repay each POSITION debt and return the position with debt cleared.
abstract contract Repay is CommandBase, RepayHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("repay", Specs.Position, Specs.Empty, Specs.Position, 0);
    }

    /// @notice Fully repay each debt and return its remaining position.
    /// @param context POSITION state and empty input for the active account.
    /// @return Positions with zero debt and all other fields preserved.
    /// @return Zero native budget credit.
    function repay(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, repayOne);
    }

    function repayOne(Execution memory exec) private {
        Position memory position = exec.unpackPositionValue();
        repay(exec.account, position);
        position.debt = 0;
        exec.outputPosition(position);
    }
}
