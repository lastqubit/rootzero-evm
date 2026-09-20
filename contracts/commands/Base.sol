// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CallerAccess} from "../core/Access.sol";
import {EndpointBase} from "../core/Endpoint.sol";
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
        uint abs;
        assembly ("memory-safe") {
            abs := context.offset
        }

        (bytes32 account, bytes calldata state, bytes calldata input, uint end) = Blocks.unpackContext(abs);
        if (end != abs + context.length) revert Blocks.InvalidBlock();

        exec.open(descriptor, account, msg.value, state, input);
    }
}
