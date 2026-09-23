// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Flags, Specs} from "./Base.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that accept account deposits.
abstract contract DepositHook {
    /// @notice Override to receive externally sourced funds for `account`.
    /// Called once per AMOUNT block. A matching BALANCE block is appended to the
    /// output after each call using the amount returned by the hook.
    /// @param account Destination account identifier.
    /// @param asset Asset identifier.
    /// @param amount Requested deposit amount.
    /// @return balance Actual amount received and represented as BALANCE state.
    function deposit(bytes32 account, bytes32 asset, uint amount) internal virtual returns (uint balance);
}

/// @notice Hook implemented by hosts that accept value-funded deposits.
abstract contract DepositPayableHook {
    /// @notice Override to receive externally sourced funds for `account`.
    /// Called once per AMOUNT block. A matching BALANCE block is appended to the
    /// output after each call using the amount returned by the hook.
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
abstract contract Deposit is CommandBase, DepositHook, ActionAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("deposit", Specs.Empty, Specs.Amount, Specs.Balance, 0);
        annotateAction(id, Actions.Deposit);
    }

    /// @notice Deposit AMOUNT input blocks into the command account and output matching BALANCE blocks.
    /// @param context Command context carrying the AMOUNT input stream.
    /// @return BALANCE block stream matching the deposited amounts.
    /// @return Zero native budget credit.
    function deposit(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, depositOne);
    }

    function depositOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackAmount();
        amount = deposit(exec.account, asset, amount);
        exec.outputBalance(asset, amount);
    }
}

/// @title DepositPayable
/// @notice Command that receives externally sourced assets and records them as BALANCE state.
/// Use `depositPayable` when the hook needs tracked access to `msg.value` via a mutable budget.
abstract contract DepositPayable is CommandBase, DepositPayableHook, ActionAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("depositPayable", Specs.Empty, Specs.Amount, Specs.Balance, Flags.Funded);
        annotateAction(id, Actions.Deposit);
    }

    /// @notice Deposit AMOUNT input blocks with access to a mutable native-value budget.
    /// @param context Command context carrying the AMOUNT input stream.
    /// @return BALANCE block stream matching the deposited amounts.
    /// @return Native value to add to the caller's budget.
    function depositPayable(bytes calldata context) external payable onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, depositPayableOne);
    }

    function depositPayableOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackAmount();
        amount = deposit(exec.account, asset, amount, exec);
        exec.outputBalance(asset, amount);
    }
}
