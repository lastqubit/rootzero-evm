// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
using Executions for Execution;

/// @notice Hook implemented by hosts that burn account assets.
abstract contract BurnHook {
    /// @notice Override to burn or consume the provided balance amount.
    /// @dev Called once per BALANCE block in state. The command consumes the entire
    /// block and ignores the returned quantity; it emits no remaining balance.
    /// Implementations must fulfill the requested burn or revert when the operation
    /// requires full consumption.
    /// @param account Caller's account identifier.
    /// @param asset Asset identifier.
    /// @param amount Amount to burn.
    /// @return Quantity actually burned. Informational to direct callers; ignored by Burn.
    function burn(bytes32 account, bytes32 asset, uint amount) internal virtual returns (uint);
}

/// @title Burn
/// @notice Command that irreversibly destroys each BALANCE state block via a virtual hook.
/// Produces no output state.
abstract contract Burn is CommandBase, BurnHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("burn", Specs.Balance, Specs.Empty, Specs.Empty, Logs.State);
    }

    /// @notice Burn each BALANCE block from the command state.
    /// @dev Logs requested BALANCE state; the hook return is not an actual-burn receipt.
    /// @param context Command context carrying the BALANCE state stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function burn(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, burnOne);
    }

    function burnOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        burn(exec.account, asset, amount);
    }
}
