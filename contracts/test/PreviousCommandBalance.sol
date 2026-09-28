// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {Execution, Executions, CommandBase, Specs} from "../commands/Base.sol";

import {Sizes} from "../codec/Specs.sol";
import {OutOfBounds} from "../utils/Errors.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";

/// @dev Previous production balance decoder; all other execution helpers stay shared.
library PreviousCommandBalance {
    function unpackBalance(Execution memory exec) internal pure returns (bytes32 asset, uint amount) {
        uint cur = exec.state;
        uint abs = uint32(cur);
        uint end = uint32(cur >> 32);
        if (Sizes.Balance > end - abs) revert OutOfBounds();
        unchecked { exec.state = cur + Sizes.Balance; }
        (asset, amount) = LegacyBlocks.unpackBalance(abs);
    }
}

abstract contract PreviousCommandCheckBalance is CommandBase {
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
        return runCommand(context, descriptor, checkBalanceOne);
    }

    function checkBalanceOne(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = PreviousCommandBalance.unpackBalance(exec);
        exec.expectBalanceConstraints(asset, amount);
        exec.outputBalance(asset, amount);
    }
}

using Executions for Execution;
abstract contract PreviousCommandWithdrawHook {
    /// @notice Override to send funds to `account`.
    /// Called once per BALANCE block in state.
    /// @param account Destination account identifier.
    /// @param asset Asset identifier.
    /// @param amount Amount to deliver.
    function withdraw(bytes32 account, bytes32 asset, uint amount) internal virtual;
}

/// @title Withdraw
/// @notice Command that delivers BALANCE state blocks to an external destination.
/// Use `withdraw` for assets being sent outside the protocol (e.g. ERC-20 transfers, ETH sends).
/// For internal balance credits, use `creditAccount` instead.
abstract contract PreviousCommandWithdraw is CommandBase, PreviousCommandWithdrawHook, ActionAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("withdraw", Specs.Balance, Specs.Empty, Specs.Empty, 0);
        annotateAction(id, Actions.Withdraw);
    }

    /// @notice Withdraw each BALANCE block from the command state to the command account.
    /// @param context Command context carrying the BALANCE state stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function withdraw(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, withdrawOne);
    }

    function withdrawOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = PreviousCommandBalance.unpackBalance(exec);
        withdraw(exec.account, asset, amount);
    }
}
