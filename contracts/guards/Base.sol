// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {InputEndpointBase} from "../core/Endpoint.sol";
import {GuardianAccess} from "../core/Access.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Specs} from "../codec/Specs.sol";
import {Nodes} from "../utils/Nodes.sol";

using Executions for Execution;

/// @title GuardBase
/// @notice Abstract base for guardian-only direct host actions.
/// Guard actions are non-payable direct calls with no command context, state, or response.
abstract contract GuardBase is InputEndpointBase, GuardianAccess {
    /// @dev Restrict execution to active guardian addresses.
    modifier onlyGuardian() {
        enforceGuardian(msg.sender);
        _;
    }

    /// @notice Publish guard metadata and a default label.
    /// @param name Guard entrypoint name and default label. It must exactly
    /// match the Solidity guard function name used by the canonical ABI.
    /// @param input Input lane: upper-half spec and lower-half logging codes.
    /// @return id Guard action node ID.
    /// @return descriptor Packed execution allocation hints and logging flags.
    function guard(
        string memory name,
        uint input
    ) internal returns (uint id, uint descriptor) {
        id = Nodes.toGuard(name, address(this));
        descriptor = endpoint(id, name, Specs.Empty, input, Specs.Empty);
    }

    /// @notice Process guardian input; entrypoint must enforce guardian access.
    /// @dev Guards have no response or budget. Logs selected INPUT before processing.
    /// Callback must advance input each iteration; empty input invokes no callback.
    /// @param id Registered guard endpoint ID used as the log prefix.
    /// @param descriptor Packed input-only endpoint descriptor.
    /// @param input Raw input block stream.
    /// @param process Internal callback that consumes and handles one item.
    function runGuard(
        uint id,
        uint descriptor,
        bytes calldata input,
        function(Execution memory) internal process
    ) internal {
        Execution memory exec;
        exec.openInput(descriptor, 0, input);
        exec.logInput(id, descriptor);
        while (exec.more()) process(exec);
        exec.expectEnd();
    }
}
