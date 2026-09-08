// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Flags, Specs} from "./Base.sol";
import {Limits, Position} from "../core/Types.sol";
import {SettleHook} from "../core/Settlement.sol";
import {Action} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";
import {Blocks, Memory} from "../codec/Blocks.sol";
import {Sizes} from "../codec/Specs.sol";
import {Cur, Decoders} from "../codec/Decoders.sol";

using Executions for Execution;
using Decoders for Cur;

/// @notice Hook implemented by hosts that fully settle positions using native value.
abstract contract SettlePayableHook {
    /// @notice Override to settle one position for `account` with a shared value budget.
    /// @dev Returning successfully asserts that the complete exact-net `debt` was
    /// satisfied. Partial fulfillment is invalid because the consuming command emits
    /// no debt remainder. Revert if the complete quantity cannot be satisfied. Fees
    /// and sourcing costs must be paid in addition to, and must not reduce, `debt`.
    /// @param account Account whose position is being settled.
    /// @param position Full position; the hook validates the counterparty and authorizes the exchange.
    /// @param limits Minimum net asset amount and maximum total debt, including fees; enforced by the hook.
    /// @param funds Mutable execution used only for its remaining native-value budget.
    function settle(bytes32 account, Position memory position, Limits memory limits, Execution memory funds) internal virtual;
}

/// @title Settle
/// @notice Command that consumes POSITION state blocks through a virtual hook.
abstract contract Settle is CommandBase, SettleHook, Action {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("settle", Specs.Position, Specs.Limits, Specs.Empty, 0);
        action(id, Actions.Settle);
    }

    /// @notice Return the registered SETTLE command ID.
    function settleId() internal view returns (uint) {
        return id;
    }

    /// @notice Settle each POSITION block from the command state.
    /// @dev The hook validates the counterparty and authorizes the exchange.
    /// @param context Command context pairing each POSITION with one LIMITS input.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function settle(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, descriptor);

        while (exec.more()) {
            Position memory position = exec.unpackPositionValue();
            settle(exec.account, position, exec.unpackLimitsValue());
        }

        return exec.close();
    }
}

/// @title SettlePayable
/// @notice Funded command that consumes POSITION state blocks through a virtual hook.
abstract contract SettlePayable is CommandBase, SettlePayableHook, Action {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("settlePayable", Specs.Position, Specs.Limits, Specs.Empty, Flags.Funded);
        action(id, Actions.Settle);
    }

    /// @notice Settle each POSITION block with access to a shared native-value budget.
    /// @dev The hook validates the counterparty and authorizes the exchange.
    /// @param context Command context pairing each POSITION with one LIMITS input.
    /// @return Empty output state.
    /// @return Native value to add to the caller's budget.
    function settlePayable(bytes calldata context) external payable onlyCommand returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, descriptor);

        while (exec.more()) {
            Position memory position = exec.unpackPositionValue();
            settle(exec.account, position, exec.unpackLimitsValue(), exec);
        }

        return exec.close();
    }
}

/// @title ExecuteSettle
/// @notice Extends the advertised settle command with memory-state pipeline execution.
/// @dev This adapter is not a separate command. It uses the command ID and settlement hook
/// inherited from `Settle` while accepting the state location used by `Pipeline`.
abstract contract ExecuteSettle is Settle {
    /// @notice Execute the inherited settle command from an internal pipeline.
    /// @dev The hook validates the counterparty and authorizes the exchange.
    /// @param account Account for which each position is settled.
    /// @param state POSITION block stream held in pipeline memory.
    /// @param input One LIMITS input block per POSITION.
    /// @param value Native value assigned to the command; must be zero.
    /// @return handled Always true because this helper executed the command.
    /// @return output Empty output state.
    /// @return credit Zero native budget credit.
    function executeSettle(
        bytes32 account,
        bytes memory state,
        bytes calldata input,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (value != 0) revert ValueNotAllowed();
        if (state.length == 0) revert Blocks.EmptyRun();
        Cur memory limits = Decoders.open(input);

        (uint abs, uint end) = Memory.bounds(state, Sizes.Position);
        while (abs < end) {
            Position memory position = Memory.unpackPositionValue(abs);
            settle(account, position, limits.unpackLimitsValue());
            unchecked {
                abs += Sizes.Position;
            }
        }

        limits.close();
        return (true, "", 0);
    }
}
