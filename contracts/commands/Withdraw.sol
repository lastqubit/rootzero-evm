// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Accounts} from "../utils/Accounts.sol";
using Executions for Execution;

/// @title WithdrawHook
/// @notice Hook implemented by hosts that withdraw account balances.
abstract contract WithdrawHook {
    /// @notice Override to send funds to `recipient`.
    /// @dev Called once per PAYOUT block in state with its recipient decoded as a nonzero EVM
    /// address. Implementations must deliver the complete amount or revert.
    /// @param recipient Address receiving the asset.
    /// @param asset Asset identifier.
    /// @param amount Amount to deliver.
    function withdraw(address recipient, bytes32 asset, uint amount) internal virtual;
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
    /// @dev Decodes each recipient with `Accounts.recipientAddr`, even for zero amounts: reverts with
    /// `ZeroAccount` for a zero recipient (a burn) and `InvalidAccount` when its top 12 bytes are set.
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
        withdraw(Accounts.recipientAddr(recipient), asset, amount);
    }
}
