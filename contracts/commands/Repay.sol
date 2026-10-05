// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {RepayHook} from "../core/Settlement.sol";
import {Position} from "../core/Types.sol";
import {Codes} from "../utils/Codes.sol";

using Executions for Execution;

/// @notice Repay each POSITION debt and emit the position with debt cleared.
abstract contract Repay is CommandBase, RepayHook {
    uint private constant STATE = Specs.Position | Codes.AccountRepay;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("repay", STATE, Specs.Empty, Specs.Position, 0);
    }

    /// @notice Fully repay each debt before emitting its remaining position.
    /// @dev Logs the original POSITION state, retaining the debt before it is cleared.
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
