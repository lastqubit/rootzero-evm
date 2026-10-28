// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {InvalidAccount} from "../utils/Errors.sol";
using Executions for Execution;

/// @title BurnHook
/// @notice Hook implemented by hosts that burn account assets.
abstract contract BurnHook {
    /// @notice Override to burn or consume the provided balance amount.
    /// @dev Called once per PAYOUT block in state. The command consumes the entire
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
/// @notice Command that irreversibly destroys each PAYOUT state block via a virtual hook.
/// A burn is a payout to the zero recipient. Produces no output state.
abstract contract Burn is CommandBase, BurnHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("burn", Specs.Payout, Specs.Empty, Specs.Empty, 0);
    }

    /// @notice Burn each PAYOUT block from the command state.
    /// @dev Reverts with `InvalidAccount` unless the recipient is zero, so value meant for a
    /// recipient is never burned. Records nothing: the command that created the PAYOUT state
    /// recorded it. The hook return is not an actual-burn receipt.
    /// @param context Command context carrying the PAYOUT state stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function burn(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, burnOne);
    }

    /// @dev Process one PAYOUT item for the Burn endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function burnOne(Execution memory exec) private {
        (bytes32 recipient, bytes32 asset, uint amount) = exec.unpackPayout();
        if (recipient != 0) revert InvalidAccount();
        burn(exec.account, asset, amount);
    }
}
