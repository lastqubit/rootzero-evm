// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that pay balances to accounts.
abstract contract PayoutHook {
    /// @notice Override to pay `amount` from `account` to `to`.
    /// Called once per paired BALANCE state block and ACCOUNT input block.
    /// @param account Source account identifier.
    /// @param to Destination account identifier.
    /// @param asset Asset identifier.
    /// @param amount Amount to pay out.
    function payout(bytes32 account, bytes32 to, bytes32 asset, uint amount) internal virtual;
}

/// @title Payout
/// @notice Command that sinks BALANCE state blocks to matching ACCOUNT input blocks.
/// Each BALANCE block is paired with one ACCOUNT block at the same position.
abstract contract Payout is CommandBase, PayoutHook, ActionAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("payout", Specs.Balance, Specs.Account, Specs.Empty, 0);
        annotateAction(id, Actions.Payout);
    }

    /// @notice Pay out BALANCE state blocks to matching ACCOUNT input blocks.
    /// @param context Command context carrying BALANCE state and matching ACCOUNT input.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function payout(
        bytes calldata context
    ) external onlyCommand returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, descriptor);

        while (exec.more()) {
            (bytes32 asset, uint amount) = exec.unpackBalance();
            payout(exec.account, exec.unpackAccount(), asset, amount);
        }

        return exec.close();
    }
}
