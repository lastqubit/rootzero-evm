// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Flags, Specs, Blocks} from "./Base.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that relay command contexts.
abstract contract RelayPayableHook {
    /// @notice Override to relay a complete destination command context.
    /// @dev Relay hooks may forward only EMPTY or BALANCE state. They must not
    /// relay POSITION or other state whose destination handling can fail:
    /// the source state is consumed before destination success is known.
    /// `funds` contains only this handoff STEP's assigned value, not the source
    /// pipeline's complete remaining budget. Implementations must consume or
    /// forward `context`; the command returns empty state when the hook completes.
    /// @param account Destination command account, also encoded in `context`.
    /// @param input Command-specific input supplied by the handoff step.
    /// Implementations define and decode this stream according to their transport.
    /// @param context Canonical CONTEXT block containing the command account,
    /// complete forwarded state, and remaining STEP stream as its input.
    /// @param funds Execution carrying value available for transport fees and
    /// destination resource funding.
    function relay(
        bytes32 account,
        bytes calldata input,
        bytes memory context,
        Execution memory funds
    ) internal virtual;
}

/// @title RelayPayable
/// @notice Command that forwards one RELAY block without pipeline state.
abstract contract RelayPayable is CommandBase, RelayPayableHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("relayPayable", Specs.Empty, Specs.Relay, Specs.Empty, Flags.HandoffFunded);
    }

    /// @notice Relay one RELAY input block with the command account and empty state.
    function relayPayable(bytes calldata context) external payable onlyCommand returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, descriptor);

        (bytes calldata input, bytes calldata steps) = exec.unpackRelay();
        relay(exec.account, input, Blocks.createContextCopy(exec.account, context[0:0], steps), exec);

        return exec.close();
    }
}

/// @title RelayBalancePayable
/// @notice Command that forwards zero or more BALANCE state blocks with one RELAY block.
/// Reverts unless the input contains exactly one RELAY block, preventing
/// the same state from being duplicated across multiple relays.
/// Produces no output state.
abstract contract RelayBalancePayable is CommandBase, RelayPayableHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("relayBalancePayable", Specs.Balance, Specs.Relay, Specs.Empty, Flags.HandoffFunded);
    }

    /// @notice Relay one RELAY input block with the command account and current state.
    /// @param context Command context carrying state and exactly one RELAY input block.
    /// @return Empty output state.
    /// @return Native value to add to the caller's budget.
    function relayBalancePayable(bytes calldata context) external payable onlyCommand returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, descriptor);

        (bytes calldata input, bytes calldata steps) = exec.unpackRelay();
        bytes calldata state = exec.takeRawBalances();
        relay(exec.account, input, Blocks.createContextCopy(exec.account, state, steps), exec);

        return exec.close();
    }
}
