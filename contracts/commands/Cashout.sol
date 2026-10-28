// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Execute} from "../codec/Execute.sol";
import {Sizes} from "../codec/Specs.sol";
import {CashoutHook} from "../core/Cash.sol";
import {Cursors} from "../utils/Cursors.sol";
import {InvalidAsset, UnexpectedInput, ZeroAccount} from "../utils/Errors.sol";

using Executions for Execution;

/// @title Cashout
/// @notice Command that pays chain-asset PAYOUT state to its recipients.
abstract contract Cashout is CommandBase, CashoutHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("cashout", Specs.Payout, Specs.Empty, Specs.Empty, 0);
    }

    /// @notice Return the registered CASHOUT command ID.
    /// @return Registered command node identifier.
    function cashoutId() internal view returns (uint) {
        return id;
    }

    /// @notice Pay chain-asset PAYOUT state to its recipients.
    /// @dev Reverts with `InvalidAsset` for another asset and `ZeroAccount` for a zero recipient.
    /// Records nothing: the command that created the PAYOUT state recorded it.
    /// @param context Command context carrying a PAYOUT state stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function cashout(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, cashoutOne);
    }

    /// @dev Process one PAYOUT item for the Cashout endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function cashoutOne(Execution memory exec) private {
        (bytes32 recipient, bytes32 asset, uint amount) = exec.unpackPayout();
        if (asset != chainAsset) revert InvalidAsset();
        if (recipient == 0) revert ZeroAccount();
        cashout(recipient, amount);
    }
}

/// @title ExecuteCashout
/// @notice Extends cashout with optimized local pipeline execution.
abstract contract ExecuteCashout is Cashout {
    /// @notice Execute cashout directly against chain-asset PAYOUT state held in memory.
    /// @param account Pipeline account; unused because each PAYOUT names its recipient.
    /// @param state PAYOUT block stream held in pipeline memory.
    /// @param inputCur Cursor over empty input required by the command schema.
    /// @param value Native value assigned to this command; returned unused as credit.
    /// @return handled Always true because this helper executed the command.
    /// @return output Empty output state.
    /// @return credit Unused assigned native value.
    function executeCashout(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (!Cursors.done(inputCur)) revert UnexpectedInput();
        account;
        (uint abs, uint end) = Execute.bounds(state, Sizes.Payout);

        while (abs < end) {
            (bytes32 recipient, bytes32 asset, uint amount) = Execute.unpackPayoutMemory(abs);
            if (asset != chainAsset) revert InvalidAsset();
            if (recipient == 0) revert ZeroAccount();
            cashout(recipient, amount);
            unchecked {
                abs += Sizes.Payout;
            }
        }

        // The default output is the shared empty bytes value; no allocation is needed.
        return (true, output, value);
    }
}
