// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {DebitAccountHook} from "../core/Settlement.sol";

using Executions for Execution;

/// @title DebitAccount
/// @notice Command that deducts ASSET_AMOUNT blocks from an account and emits matching BALANCE state.
/// Use for internally recording debits. The virtual `debitAccount` hook is called once per
/// ASSET_AMOUNT block.
abstract contract DebitAccount is CommandBase, DebitAccountHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("debitAccount", Specs.Empty, Specs.AssetAmount, Specs.Balance, 0);
    }

    /// @notice Return the registered DEBIT_ACCOUNT command ID.
    /// @return Registered command node identifier.
    function debitAccountId() internal view returns (uint) {
        return id;
    }

    /// @notice Debit ASSET_AMOUNT input blocks from the command account and output matching BALANCE blocks.
    /// @param context Command context carrying the ASSET_AMOUNT input stream.
    /// @return BALANCE block stream matching the debited amounts.
    /// @return Zero native budget credit.
    function debitAccount(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, debitAccountOne);
    }

    /// @dev Process one ASSET_AMOUNT item for the DebitAccount endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function debitAccountOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackAssetAmount();
        debitAccount(exec.account, asset, amount);
        exec.outputBalance(asset, amount);
    }
}
