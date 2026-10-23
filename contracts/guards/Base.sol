// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Specs} from "../codec/Specs.sol";
import {GuardianAccess} from "../core/Access.sol";
import {InputEndpointBase} from "../core/Endpoint.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Nodes} from "../utils/Nodes.sol";

using Executions for Execution;

/// @title GuardBase
/// @notice Abstract base for guardian-only direct host actions.
/// Guard actions are non-payable direct calls with no command context, state, or response.
/// Guards emit no execution record; callers or hooks log what they need.
abstract contract GuardBase is InputEndpointBase, GuardianAccess {
    /// @dev Restrict execution to active guardian addresses.
    modifier onlyGuardian() {
        enforceGuardian(msg.sender);
        _;
    }

    /// @notice Publish guard metadata and a default label.
    /// @param name Guard entrypoint name and default label. It must exactly
    /// match the Solidity guard function name used by the canonical ABI.
    /// @param input Input block specification.
    /// @return id Guard action node ID.
    /// @return descriptor Packed execution allocation hints.
    function guard(string memory name, uint input) internal returns (uint id, uint descriptor) {
        return guard(name, input, 0);
    }

    /// @notice Register a guard with identity flags.
    /// @param name Canonical endpoint function name used to derive its ABI selector.
    /// @param input Input block specification or named lane.
    /// @param flags Endpoint behavior flags and logging hints for callers.
    /// @return id Registered endpoint node identifier.
    /// @return descriptor Packed source and output allocation hints with internal execution flags.
    function guard(string memory name, uint input, uint flags) internal returns (uint id, uint descriptor) {
        if (flags > 255) revert Specs.InvalidSpec();
        id = Nodes.toGuard(name, hostAddr(), uint8(flags));
        descriptor = endpoint(id, name, Specs.Empty, input, Specs.Empty);
    }

    /// @notice Process guardian input; entrypoint must enforce guardian access.
    /// @dev Guards have no account, response, or budget. The callback must advance
    /// input each iteration; empty input invokes no callback.
    /// @param descriptor Packed input-only endpoint descriptor.
    /// @param input Raw input block stream.
    /// @param process Internal callback that consumes and handles one item.
    function runGuard(
        uint descriptor,
        bytes calldata input,
        function(Execution memory) internal process
    ) internal {
        Execution memory exec;
        exec.openInput(descriptor, 0, input);
        while (exec.more()) process(exec);
        exec.expectEnd();
    }
}
