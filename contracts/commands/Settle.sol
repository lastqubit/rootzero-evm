// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Flags, Specs} from "./Base.sol";
import {Execute} from "../codec/Execute.sol";
import {Keys} from "../codec/Keys.sol";
import {Logs} from "../codec/Logs.sol";
import {Sizes} from "../codec/Specs.sol";
import {SettleHook} from "../core/Settlement.sol";
import {Position} from "../core/Types.sol";
import {Codes} from "../utils/Codes.sol";
import {Cursors} from "../utils/Cursors.sol";
import {UnexpectedInput} from "../utils/Errors.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that fully settle positions using native value.
abstract contract SettlePayableHook {
    /// @notice Override to settle one position for `account` with a shared value budget.
    /// @dev Returning successfully asserts that the complete final `debt` was
    /// satisfied. Partial fulfillment is invalid because the consuming command emits
    /// no debt remainder. Producers handle fees before creating the position:
    /// `amount` is the final net receipt and `debt` the final total payment.
    /// Producers enforce limits before emitting positions. Apply both quantities exactly, without extra fees.
    /// @param account Account whose position is being settled.
    /// @param position Full position with trusted account format; the hook applies exchange authorization.
    /// @param funds Mutable execution used only for its remaining native-value budget.
    function settle(bytes32 account, Position memory position, Execution memory funds) internal virtual;
}

/// @title Settle
/// @notice Command that consumes POSITION state blocks through a virtual hook.
abstract contract Settle is CommandBase, SettleHook {
    uint private constant STATE = Specs.Position | Codes.AccountSettle;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("settle", STATE, Specs.Empty, Specs.Empty, 0);
    }

    /// @notice Return the registered SETTLE command ID.
    function settleId() internal view returns (uint) {
        return id;
    }

    /// @notice Settle each POSITION block from the command state.
    /// @dev Account format is trusted from the producer; the hook applies exchange authorization.
    /// @dev Logs the consumed State stream before hooks, including empty batches.
    /// @param context Command context carrying POSITION state and empty input.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function settle(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, settleOne);
    }

    function settleOne(Execution memory exec) private {
        Position memory position = exec.unpackPositionValue();
        settle(exec.account, position);
    }
}

/// @title SettlePayable
/// @notice Funded command that consumes POSITION state blocks through a virtual hook.
abstract contract SettlePayable is CommandBase, SettlePayableHook {
    uint private constant STATE = Specs.Position | Codes.AccountSettle;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("settlePayable", STATE, Specs.Empty, Specs.Empty, Flags.Funded);
    }

    /// @notice Settle each POSITION block with access to a shared native-value budget.
    /// @dev Account format is trusted from the producer; the hook applies exchange authorization.
    /// @dev Logs the consumed State stream before hooks, including empty batches.
    /// @param context Command context carrying POSITION state and empty input.
    /// @return Empty output state.
    /// @return Native value to add to the caller's budget.
    function settlePayable(bytes calldata context) external payable onlyCommand returns (bytes memory, uint) {
        return runCommand(id, descriptor, context, settlePayableOne);
    }

    function settlePayableOne(Execution memory exec) private {
        Position memory position = exec.unpackPositionValue();
        settle(exec.account, position, exec);
    }
}

/// @title ExecuteSettle
/// @notice Extends the advertised settle command with memory-state pipeline execution.
/// @dev This adapter is not a separate command. It uses the command ID and settlement hook
/// inherited from `Settle` while accepting the state location used by `Pipeline`.
abstract contract ExecuteSettle is Settle {
    /// @notice Execute the inherited settle command from an internal pipeline.
    /// @dev Account format is trusted from the producer; the hook applies exchange authorization.
    /// @dev Logs STATE before hooks, matching the calldata command.
    /// @param account Account for which each position is settled.
    /// @param state POSITION block stream held in pipeline memory.
    /// @param inputCur Cursor over empty command input.
    /// @param value Native value assigned to the command; returned unused as credit.
    /// @return handled Always true because this helper executed the command.
    /// @return output Empty output state.
    /// @return credit Unused assigned native value.
    function executeSettle(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (!Cursors.done(inputCur)) revert UnexpectedInput();
        (uint abs, uint end) = Execute.bounds(state, Sizes.Position);

        Logs.memCopyWrap(settleId(), Keys.State, state);

        while (abs < end) {
            settle(account, Execute.unpackPositionMemory(abs));
            unchecked {
                abs += Sizes.Position;
            }
        }

        // The default output is the shared empty bytes value; no allocation is needed.
        return (true, output, value);
    }
}
