// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Memory} from "../codec/Blocks.sol";
import {Sizes} from "../codec/Specs.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";
import {InvalidAsset, UnexpectedInput} from "../utils/Errors.sol";
import {CashoutHook} from "../core/Cash.sol";

using Executions for Execution;

/// @title Cashout
/// @notice Command that withdraws requested chain-asset amounts from its account.
abstract contract Cashout is CommandBase, CashoutHook, ActionAnnot {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("cashout", Specs.Balance, Specs.Empty, Specs.Empty, 0);
        annotateAction(id, Actions.Cashout);
    }

    /// @notice Return the registered CASHOUT command ID.
    function cashoutId() internal view returns (uint) {
        return id;
    }

    /// @notice Withdraw chain-asset BALANCE state from the command account.
    /// @param context Command context carrying a BALANCE state stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function cashout(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, cashoutOne);
    }

    function cashoutOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        if (asset != chainAsset) revert InvalidAsset();
        cashout(exec.account, amount);
    }
}

/// @title ExecuteCashout
/// @notice Extends cashout with optimized local pipeline execution.
abstract contract ExecuteCashout is Cashout {
    /// @notice Execute cashout directly against chain-asset BALANCE state held in memory.
    /// @param account Account whose chain asset is withdrawn.
    /// @param state BALANCE block stream held in pipeline memory.
    /// @param input Empty input required by the command schema.
    /// @param value Native value assigned to this command; returned unused as credit.
    /// @return handled Always true because this helper executed the command.
    /// @return output Empty output state.
    /// @return credit Unused assigned native value.
    function executeCashout(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (input.length != 0) revert UnexpectedInput();
        (uint abs, uint end) = Memory.bounds(state, Sizes.Balance);

        while (abs < end) {
            (bytes32 asset, uint amount) = Memory.unpackBalance(abs);
            if (asset != chainAsset) revert InvalidAsset();
            cashout(account, amount);
            unchecked {
                abs += Sizes.Balance;
            }
        }

        return (true, "", value);
    }
}
