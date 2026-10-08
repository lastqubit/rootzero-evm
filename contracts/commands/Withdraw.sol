// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
using Executions for Execution;

/// @notice Hook implemented by hosts that withdraw account balances.
abstract contract WithdrawHook {
    /// @notice Override to send funds to `account`.
    /// @dev Called once per BALANCE block in state.
    /// @param account Destination account identifier.
    /// @param asset Asset identifier.
    /// @param amount Amount to deliver.
    function withdraw(bytes32 account, bytes32 asset, uint amount) internal virtual;
}

/// @title Withdraw
/// @notice Command that delivers BALANCE state blocks to an external destination.
/// Use `withdraw` for assets being sent outside the protocol (e.g. ERC-20 transfers, ETH sends).
/// For internal balance credits, use `creditAccount` instead.
abstract contract Withdraw is CommandBase, WithdrawHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("withdraw", Specs.Balance, Specs.Empty, Specs.Empty, Logs.State);
    }

    /// @notice Withdraw each BALANCE block from the command state to the command account.
    /// @dev Logs the complete STATE after processing, including an empty batch.
    /// The state spec identifies Balance; endpoint interpretation is defined offchain.
    /// @param context Command context carrying the BALANCE state stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function withdraw(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, withdrawOne);
    }

    function withdrawOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        withdraw(exec.account, asset, amount);
    }
}
