// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {Execution, Executions, CommandBase, Flags, Specs} from "./Base.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that accept account deposits.
abstract contract DepositHook {
    /// @notice Override to receive externally sourced funds for `account`.
    /// @param account Destination account identifier.
    /// @param asset Asset identifier.
    /// @param amount Requested deposit amount.
    /// @return balance Actual amount received and represented as BALANCE state.
    function deposit(bytes32 account, bytes32 asset, uint amount) internal virtual returns (uint balance);
}

/// @notice Hook implemented by hosts that accept value-funded deposits.
abstract contract DepositPayableHook {
    /// @notice Override to receive externally sourced funds for `account`.
    /// @param account Destination account identifier.
    /// @param asset Asset identifier.
    /// @param amount Requested deposit amount.
    /// @param funds Mutable execution used only for its remaining native-value budget.
    /// @return balance Actual amount received and represented as BALANCE state.
    function deposit(
        bytes32 account,
        bytes32 asset,
        uint amount,
        Execution memory funds
    ) internal virtual returns (uint balance);
}

/// @title Deposit
/// @notice Command that receives externally sourced assets and records them as BALANCE state.
/// Use `deposit` for assets arriving from outside the protocol (e.g. ERC-20 transfers, ETH).
/// For internal balance deductions, use `debitAccount` instead.
abstract contract Deposit is CommandBase, DepositHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("deposit", Specs.Empty, Specs.AssetAmount, Specs.Balance, Logs.Output);
    }

    /// @notice Deposit ASSET_AMOUNT input blocks into the command account and output matching BALANCE blocks.
    /// @dev Logs the complete Output stream with the amounts returned by the hooks.
    /// @param context Command context carrying the ASSET_AMOUNT input stream.
    /// @return BALANCE block stream matching the deposited amounts.
    /// @return Zero native budget credit.
    function deposit(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, depositOne);
    }

    function depositOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackAssetAmount();
        amount = deposit(exec.account, asset, amount);
        exec.outputBalance(asset, amount);
    }
}

/// @title DepositPayable
/// @notice Command that receives externally sourced assets and records them as BALANCE state.
/// Use `depositPayable` when the hook needs tracked access to `msg.value` via a mutable budget.
abstract contract DepositPayable is CommandBase, DepositPayableHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("depositPayable", Specs.Empty, Specs.AssetAmount, Specs.Balance, Logs.Output | Flags.Funded);
    }

    /// @notice Deposit ASSET_AMOUNT input blocks with access to a mutable native-value budget.
    /// @dev Logs the complete Output stream with the amounts returned by the hooks.
    /// @param context Command context carrying the ASSET_AMOUNT input stream.
    /// @return BALANCE block stream matching the deposited amounts.
    /// @return Native value to add to the caller's budget.
    function depositPayable(bytes calldata context) external payable onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, depositPayableOne);
    }

    function depositPayableOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackAssetAmount();
        amount = deposit(exec.account, asset, amount, exec);
        exec.outputBalance(asset, amount);
    }
}
