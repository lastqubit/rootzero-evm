// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Execute} from "../codec/Execute.sol";

/// @notice Check each BALANCE amount against paired inclusive BALANCE_CONSTRAINTS and preserve the balance.
/// @dev Checks asset identity and quantity, not authorization or backing.
abstract contract CheckBalance is CommandBase {
    using Executions for Execution;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("checkBalance", Specs.Balance, Specs.BalanceConstraints, Specs.Balance, 0);
    }

    /// @notice Return the registered checkBalance command ID.
    function checkBalanceId() internal view returns (uint) {
        return id;
    }

    /// @notice Require the expected asset and minimum <= amount <= maximum for each balance.
    /// @param context Command context with one BALANCE_CONSTRAINTS input per BALANCE state block.
    /// @return Unchanged BALANCE blocks.
    /// @return Zero native budget credit.
    function checkBalance(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, checkBalanceOne);
    }

    function checkBalanceOne(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        exec.expectBalanceConstraints(asset, amount);
        exec.outputBalance(asset, amount);
    }
}

/// @notice Extends checkBalance with direct validation of memory-backed pipeline state.
abstract contract ExecuteCheckBalance is CheckBalance {
    /// @notice Validate balances in place without unpacking or copying their blocks.
    /// @param state BALANCE block stream in memory.
    /// @param inputCur Cursor over exactly one calldata BALANCE_CONSTRAINTS block per balance.
    /// @param value Assigned native budget, returned unused.
    /// @return handled Always true.
    /// @return output The original state buffer, unchanged.
    /// @return credit Unused assigned native budget.
    function executeCheckBalance(
        bytes32,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal pure returns (bool handled, bytes memory output, uint credit) {
        Execute.checkBalances(state, inputCur);

        return (true, state, value);
    }
}
