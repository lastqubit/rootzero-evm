// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {Execute} from "../codec/Execute.sol";
import {Sizes} from "../codec/Specs.sol";
import {UnexpectedState} from "../utils/Errors.sol";

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
    function debitAccountId() internal view returns (uint) {
        return id;
    }

    /// @notice Debit ASSET_AMOUNT input blocks from the command account and output matching BALANCE blocks.
    /// @param context Command context carrying the ASSET_AMOUNT input stream.
    /// @return BALANCE block stream matching the debited amounts.
    /// @return Zero native budget credit.
    function debitAccount(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, debitAccountOne);
    }

    function debitAccountOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackAssetAmount();
        debitAccount(exec.account, asset, amount);
        exec.outputBalance(asset, amount);
    }
}

/// @title ExecuteDebitAccount
/// @notice Extends the advertised debit-account command with optimized pipeline execution.
/// @dev This adapter is not a separate command. It uses the command ID and account hook
/// inherited from `DebitAccount` while decoding its fixed-stride input directly from calldata.
abstract contract ExecuteDebitAccount is DebitAccount {
    /// @notice Execute the inherited debit-account command from an internal pipeline.
    /// @param account Account whose funds are debited.
    /// @param state Empty pipeline state required by the command schema.
    /// @param inputCur ASSET_AMOUNT block stream.
    /// @param value Native value assigned to the command; returned unused as credit.
    /// @return handled Always true because this helper executed the command.
    /// @return output BALANCE block stream matching the debited amounts.
    /// @return credit Unused assigned native value.
    function executeDebitAccount(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (state.length != 0) revert UnexpectedState();
        (uint abs, uint end) = Execute.bounds(inputCur, Sizes.AssetAmount);
        uint i;
        unchecked {
            (i, output) = Execute.allocateBalances((end - abs) / Sizes.AssetAmount);
        }

        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
            debitAccount(account, asset, amount);
            i = Execute.writeBalance(i, asset, amount);
            unchecked {
                abs += Sizes.AssetAmount;
            }
        }

        return (true, output, value);
    }
}
