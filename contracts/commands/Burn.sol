// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";
using Executions for Execution;

/// @notice Hook implemented by hosts that burn account assets.
abstract contract BurnHook {
    /// @notice Override to burn or consume the provided balance amount.
    /// Called once per BALANCE block in state.
    /// @param account Caller's account identifier.
    /// @param asset Asset identifier.
    /// @param amount Amount to burn.
    /// @return Amount actually burned (may differ from `amount` for partial burns).
    function burn(bytes32 account, bytes32 asset, uint amount) internal virtual returns (uint);
}

/// @title Burn
/// @notice Command that irreversibly destroys each BALANCE state block via a virtual hook.
/// Produces no output state.
abstract contract Burn is CommandBase, BurnHook, ActionAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("burn", Specs.Balance, Specs.Empty, Specs.Empty, 0);
        annotateAction(id, Actions.Burn);
    }

    /// @notice Burn each BALANCE block from the command state.
    /// @param context Command context carrying the BALANCE state stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function burn(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, burnOne);
    }

    function burnOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        burn(exec.account, asset, amount);
    }
}
