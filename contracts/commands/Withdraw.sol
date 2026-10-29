// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {ZeroAccount} from "../utils/Errors.sol";
using Executions for Execution;

/// @title WithdrawHook
/// @notice Hook implemented by hosts that withdraw account balances.
abstract contract WithdrawHook {
    /// @notice Override to send funds to `recipient`.
    /// @dev Called once per PAYOUT block in state with its nonzero recipient, a native address
    /// left-padded to 32 bytes. Implementations turn it into the address they pay and revert for
    /// one they can't pay; an EVM host uses `Accounts.recipientAddr`. They must deliver the
    /// complete amount or revert.
    /// @param recipient Native address receiving the asset, as a 32-byte word.
    /// @param asset Asset identifier.
    /// @param amount Amount to deliver.
    function withdraw(bytes32 recipient, bytes32 asset, uint amount) internal virtual;
}

/// @title Withdraw
/// @notice Command that delivers PAYOUT state blocks to their recipients outside the protocol.
/// Use `withdraw` for assets being sent outside the protocol (e.g. ERC-20 transfers, ETH sends).
/// For internal balance credits, use `creditAccount` instead.
abstract contract Withdraw is CommandBase, WithdrawHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("withdraw", Specs.Payout, Specs.Empty, Specs.Empty, 0);
    }

    /// @notice Withdraw each PAYOUT block from the command state to its recipient.
    /// @dev Reverts with `ZeroAccount` for a zero recipient (a burn), even for zero amounts, and
    /// passes every other recipient word to the hook, which turns it into an address.
    /// Records nothing: the command that created the PAYOUT state recorded it.
    /// @param context Command context carrying the PAYOUT state stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function withdraw(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, withdrawOne);
    }

    /// @dev Process one PAYOUT item for the Withdraw endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function withdrawOne(Execution memory exec) private {
        (bytes32 recipient, bytes32 asset, uint amount) = exec.unpackPayout();
        if (recipient == 0) revert ZeroAccount();
        withdraw(recipient, asset, amount);
    }
}
