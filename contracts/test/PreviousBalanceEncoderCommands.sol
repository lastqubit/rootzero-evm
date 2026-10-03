// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {Execution, Executions, CommandBase, Specs} from "../commands/Base.sol";

import {LegacyBuffers} from "./LegacyBuffers.sol";
import {Sizes} from "../codec/Specs.sol";
import {DebitAccountHook} from "../core/Settlement.sol";

/// @dev Frozen pre-migration outputBalance. Decoder, runner, and reservation semantics stay shared.
library PreviousBalanceOutput {
    function outputBalance(Execution memory exec, bytes32 asset, uint amount) internal pure {
        uint i;
        (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, Sizes.B64, Sizes.B64);
        LegacyBlocks.writeBalance(exec.buffer, i, asset, amount);
    }
}

abstract contract PreviousEncoderCheckBalance is CommandBase {
    using Executions for Execution;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("checkBalance", Specs.Balance, Specs.BalanceConstraints, Specs.Balance, 0);
    }

    /// @notice Return the registered checkBalance command ID.
    function checkBalanceId() internal view returns (uint) {
        return id;
    }

    /// @notice Require the expected asset and minimum <= amount <= maximum for each balance.
    /// @param context Command context with one BALANCE_CONSTRAINTS input per BALANCE state block.
    /// @return Unchanged BALANCE blocks.
    /// @return Zero native budget credit.
    function checkBalance(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, checkBalanceOne);
    }

    function checkBalanceOne(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        exec.expectBalanceConstraints(asset, amount);
        PreviousBalanceOutput.outputBalance(exec, asset, amount);
    }
}

using Executions for Execution;
abstract contract PreviousEncoderDebitAccount is CommandBase, DebitAccountHook {
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
        PreviousBalanceOutput.outputBalance(exec, asset, amount);
    }
}
