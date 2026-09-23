// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { PeerAccess } from "../core/Access.sol";
import { Specs } from "../codec/Specs.sol";
import { InputEndpointBase } from "../core/Endpoint.sol";
import { Nodes } from "../utils/Nodes.sol";
import { Execution, Executions } from "../execution/Execution.sol";

/// @title PortBase
/// @notice Abstract base for peer-facing rootzero ports.
/// Ports handle inter-host operations between cooperating hosts.
/// Access is restricted to trusted peer callers via `onlyPeer`.
/// @dev A trusted peer is a fully trusted extension of the receiving host and
/// may use every exposed port. Its behavior, caller validation, dependencies,
/// and upgrade authority must be fully validated before admission. onlyPeer
/// authenticates the caller once at entry; batch operations do not add separate
/// peer-specific authorization by port, asset, or direction. Operation validity
/// and accounting invariants still apply. Do not admit partially trusted peers.
abstract contract PortBase is PeerAccess, InputEndpointBase {

    /// @dev Restrict execution to trusted callers, excluding the commander.
    modifier onlyPeer() {
        enforcePeer(msg.sender);
        _;
    }

    /// @notice Return the host node ID corresponding to the current caller.
    /// @dev Encodes `msg.sender` as a host ID using the local-chain host layout.
    /// @return Host node ID for `msg.sender`.
    function caller() internal view returns (uint) {
        return Nodes.toHost(msg.sender);
    }

    /// @notice Publish port metadata and a default label.
    /// @param name Port entrypoint name and default label. It must exactly
    /// match the Solidity port function name used by the canonical ABI.
    /// @param input Input block specification.
    /// @param output Output block specification.
    /// @param flags Packed port behavior flags.
    /// @return id Port node ID.
    /// @return descriptor Packed endpoint lane metadata and flags.
    function port(
        string memory name,
        uint input,
        uint output,
        uint8 flags
    ) internal returns (uint id, uint descriptor) {
        descriptor = Executions.describe(Specs.Empty, input, output, flags);
        return port(name, descriptor);
    }

    /// @notice Publish an already constructed port descriptor and default label.
    /// @param name Port entrypoint name and default label. It must exactly
    /// match the Solidity port function name used by the canonical ABI.
    /// @param descriptor Packed port endpoint descriptor.
    /// @return id Port node ID.
    /// @return published Published endpoint descriptor.
    function port(
        string memory name,
        uint descriptor
    ) internal returns (uint id, uint published) {
        id = Nodes.toPort(name, address(this), uint8(descriptor));
        published = endpoint(id, name, descriptor);
    }

    /// @notice Process a port input stream through a callback per item.
    /// @dev Opens raw input with `msg.value` as its initial budget and no account
    /// or state source. The callback must advance input on each iteration; empty
    /// input invokes no callback. No progress guard is enforced. Access control
    /// remains the caller's responsibility.
    /// @param input Input block stream.
    /// @param descriptor Packed input-only endpoint descriptor.
    /// @param process Internal callback that consumes and processes one item.
    /// @return output Final encoded response block stream.
    /// @return credit Remaining native-value budget.
    function runPort(
        bytes calldata input,
        uint descriptor,
        function(Execution memory) internal process
    ) internal returns (bytes memory output, uint credit) {
        Execution memory exec;
        Executions.openInput(exec, descriptor, msg.value, input);
        while (Executions.more(exec)) {
            process(exec);
        }
        return Executions.close(exec);
    }
}
