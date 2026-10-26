// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {Execution, Executions, CommandBase, Flags, Specs} from "./Base.sol";

using Executions for Execution;

/// @title DepositHook
/// @notice Hook implemented by hosts that accept account deposits.
abstract contract DepositHook {
    /// @notice Override to receive externally sourced funds for `account`.
    /// @param account Destination account identifier.
    /// @param asset Asset identifier.
    /// @param amount Requested deposit amount.
    /// @return balance Actual amount received and represented as BALANCE state.
    function deposit(bytes32 account, bytes32 asset, uint amount) internal virtual returns (uint balance);
}

/// @title DepositPayableHook
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
/// For internal balance deductions, use `debitAccount` instead. Each TRUST state block names
/// a vouched asset and pairs, in order, with one AMOUNT input block; pipelines start with the
/// commander's `vouch` to produce that state, so only trusted assets can be deposited.
abstract contract Deposit is CommandBase, DepositHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("deposit", Specs.Trust, Specs.Amount, Specs.Balance, Logs.Output);
    }

    /// @notice Deposit each TRUST asset by its paired AMOUNT into the command account and output BALANCE blocks.
    /// @dev Hints callers to record the OUTPUT stream with the amounts returned by the hooks.
    /// A TRUST without an AMOUNT, or an AMOUNT without a TRUST, reverts.
    /// @param context Command context carrying TRUST state and the paired AMOUNT input stream.
    /// @return BALANCE block stream matching the deposited amounts.
    /// @return Zero native budget credit.
    function deposit(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, depositOne);
    }

    /// @dev Process one TRUST/AMOUNT pair for the Deposit endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function depositOne(Execution memory exec) private {
        bytes32 asset = bytes32(exec.unpackTrust());
        uint amount = exec.unpackAmount();
        amount = deposit(exec.account, asset, amount);
        exec.outputBalance(asset, amount);
    }
}

/// @title DepositPayable
/// @notice Command that receives externally sourced assets and records them as BALANCE state.
/// Use `depositPayable` when the hook needs tracked access to `msg.value` via a mutable budget.
/// Takes TRUST state paired in order with AMOUNT input, like `deposit`.
abstract contract DepositPayable is CommandBase, DepositPayableHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("depositPayable", Specs.Trust, Specs.Amount, Specs.Balance, Logs.Output | Flags.Funded);
    }

    /// @notice Deposit each TRUST asset by its paired AMOUNT with access to a mutable native-value budget.
    /// @dev Hints callers to record the OUTPUT stream with the amounts returned by the hooks.
    /// @param context Command context carrying TRUST state and the paired AMOUNT input stream.
    /// @return BALANCE block stream matching the deposited amounts.
    /// @return Native value to add to the caller's budget.
    function depositPayable(bytes calldata context) external payable onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, depositPayableOne);
    }

    /// @dev Process one TRUST/AMOUNT pair for the DepositPayable endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function depositPayableOne(Execution memory exec) private {
        bytes32 asset = bytes32(exec.unpackTrust());
        uint amount = exec.unpackAmount();
        amount = deposit(exec.account, asset, amount, exec);
        exec.outputBalance(asset, amount);
    }
}
