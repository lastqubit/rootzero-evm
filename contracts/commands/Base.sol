// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CallerAccess} from "../core/Access.sol";
import {EndpointBase} from "../core/Endpoint.sol";
import {Buffers} from "../codec/Buffers.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Specs} from "../codec/Specs.sol";
import {HostAmount, Position} from "../core/Types.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Flags} from "../utils/Flags.sol";
import {Nodes} from "../utils/Nodes.sol";

using Executions for Execution;

/// @title CommandBase
/// @notice Abstract base for all rootzero command contracts.
/// Provides access control modifiers and command endpoint metadata helpers.
abstract contract CommandBase is CallerAccess, EndpointBase {
    /// @dev Thrown when `onlyActive` finds that `deadline` has already passed.
    error Expired();
    /// @dev Restrict execution to trusted callers.
    modifier onlyCommand() {
        enforceCaller(msg.sender);
        _;
    }

    /// @dev Restrict execution to invocations where `deadline` is in the future.
    /// @param deadline Unix timestamp after which the invocation is considered expired.
    modifier onlyActive(uint deadline) {
        if (deadline < block.timestamp) revert Expired();
        _;
    }

    /// @notice Publish command metadata and a default label.
    /// @param name Command entrypoint name and default label. It must exactly
    /// match the Solidity command function name used by the canonical ABI.
    /// @param state State block specification.
    /// @param input Input block specification.
    /// @param output Output block specification.
    /// @param flags Packed command behavior flags.
    /// @return id Command node ID.
    /// @return descriptor Packed endpoint lane metadata and flags.
    function command(
        string memory name,
        uint state,
        uint input,
        uint output,
        uint8 flags
    ) internal returns (uint id, uint descriptor) {
        descriptor = Executions.describe(state, input, output, flags);
        return command(name, descriptor);
    }

    /// @notice Publish an already constructed command descriptor and default label.
    /// @param name Command entrypoint name and default label. It must exactly
    /// match the Solidity command function name used by the canonical ABI.
    /// @param descriptor Packed command endpoint descriptor.
    /// @return id Command node ID.
    /// @return published Published endpoint descriptor.
    function command(string memory name, uint descriptor) internal returns (uint id, uint published) {
        id = Nodes.toCommand(name, address(this), uint8(descriptor));
        published = endpoint(id, name, descriptor);
    }

    /// @notice Decode one command context and open bounded state and input sources.
    /// @dev Rejects empty input, trailing bytes, and additional context blocks.
    /// The command's decode and loop implementation defines source semantics.
    /// Closing requires both sources to have been consumed completely.
    /// @param context Exactly one CONTEXT block carrying the account, state, and input.
    /// @param descriptor Packed command endpoint descriptor.
    /// @return exec Execution with a resizable output writer initialized from its descriptor hint.
    function openCommand(bytes calldata context, uint descriptor) internal view returns (Execution memory exec) {
        exec.openContext(descriptor, msg.value, context);
    }

    /// @notice Run a context through a callback for each batch item.
    /// @dev Opens exactly one CONTEXT using `msg.value` as its initial budget.
    /// The callback shares the execution and must advance state or input on each
    /// iteration until both sources are consumed. No progress guard is enforced.
    /// Source pairing, parent boundaries, and access control remain the caller's
    /// responsibility.
    /// @param context Exactly one CONTEXT block carrying account, state, and input.
    /// @param descriptor Packed endpoint descriptor.
    /// @param process Internal callback that consumes and processes one batch item.
    /// @return output Final encoded output block stream.
    /// @return credit Remaining native-value budget.
    function runCommand(
        bytes calldata context,
        uint descriptor,
        function(Execution memory) internal process
    ) internal returns (bytes memory output, uint credit) {
        Execution memory exec = openCommand(context, descriptor);

        while (Executions.more(exec)) {
            process(exec);
        }

        // Normal loop exit already proves that neither source has unread bytes.
        output = exec.output.length == 0 ? new bytes(0) : Buffers.finish(exec.writer, exec.output);
        credit = exec.budget;
        exec.budget = 0;
    }

    /// @notice Run a context through a callback exactly once.
    /// @dev Opens exactly one CONTEXT using `msg.value` as its initial budget.
    /// Invokes the callback even when both sources are empty, then requires both
    /// sources to be fully consumed. The callback defines required input and
    /// state shapes; parent boundaries and access control remain the caller's
    /// responsibility.
    /// @param context Exactly one CONTEXT block carrying account, state, and input.
    /// @param descriptor Packed endpoint descriptor.
    /// @param process Internal callback that processes the complete execution.
    /// @return output Final encoded output block stream.
    /// @return credit Remaining native-value budget.
    function runCommandOnce(
        bytes calldata context,
        uint descriptor,
        function(Execution memory) internal process
    ) internal returns (bytes memory output, uint credit) {
        Execution memory exec = openCommand(context, descriptor);
        process(exec);
        return Executions.close(exec);
    }
}
