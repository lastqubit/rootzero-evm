// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Position} from "../core/Types.sol";
import {BookHook} from "../core/Settlement.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";
import {Memory} from "../codec/Blocks.sol";
import {Sizes} from "../codec/Specs.sol";
import {UnexpectedInput, UnexpectedValue} from "../utils/Errors.sol";

using Executions for Execution;

/// @title Book
/// @notice Consume Rootzero-backed POSITION state through the book hook.
abstract contract Book is CommandBase, BookHook, ActionAnnot {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("book", Specs.Position, Specs.Empty, Specs.Empty, 0);
        annotateAction(id, Actions.Book);
    }

    /// @notice Return the registered BOOK command ID.
    function bookId() internal view returns (uint) {
        return id;
    }

    /// @notice Book each POSITION after requiring a zero counterparty.
    /// @param context Command context with POSITION state and empty input.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function book(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, descriptor);

        while (exec.more()) {
            (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty) = exec.unpackPosition();
            if (counterparty != 0) revert UnexpectedValue();
            book(exec.account, exec.account, asset, amount, liability, debt);
        }

        return exec.close();
    }
}

/// @title ExecuteBook
/// @notice Execute the advertised book command against pipeline memory state.
abstract contract ExecuteBook is Book {
    /// @notice Book a POSITION stream after requiring zero counterparties.
    /// @param account Account whose positions are booked.
    /// @param state POSITION block stream held in memory.
    /// @param input Empty input required by the command schema.
    /// @param value Assigned native value; must be zero.
    /// @return handled Always true after successful execution.
    /// @return output Empty output state.
    /// @return credit Zero native budget credit.
    function executeBook(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (value != 0) revert ValueNotAllowed();
        if (input.length != 0) revert UnexpectedInput();

        (uint abs, uint end) = Memory.bounds(state, Sizes.Position);
        while (abs < end) {
            Position memory position = Memory.unpackPositionValue(abs);
            if (position.counterparty != 0) revert UnexpectedValue();
            book(account, account, position.asset, position.amount, position.liability, position.debt);
            unchecked {
                abs += Sizes.Position;
            }
        }

        return (true, "", 0);
    }
}
