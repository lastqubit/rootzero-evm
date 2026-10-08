// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {PeerAccess} from "../core/Access.sol";
import {Specs} from "../codec/Specs.sol";
import {InputEndpointBase} from "../core/Endpoint.sol";
import {Nodes} from "../utils/Nodes.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

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
/// Trusted peers are responsible for supplied account validity; receiving ports
/// need not repeat account-format validation. A faulty trusted integration can
/// supply malformed accounts, and the receiving host does not guarantee rejection.
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
    /// @param flags Combined behavior and logging identity flags.
    /// @return id Port node ID.
    /// @return descriptor Packed execution allocation hints and explicit logging selections.
    function port(string memory name, uint input, uint output, uint flags) internal returns (uint id, uint descriptor) {
        if (flags > 255 || flags & (Logs.State ^ Logs.Execution) != 0) revert Specs.InvalidSpec();
        id = Nodes.toPort(name, address(this), uint8(flags));
        descriptor = endpoint(id, name, Specs.Empty, input, output);
    }

    /// @notice Process a port input stream through a callback per item.
    /// @dev Opens raw input with `msg.value` as its initial budget, a zero account,
    /// and no state source. The callback must advance input on each iteration; empty
    /// input invokes no callback. No progress guard is enforced. Access control
    /// remains the caller's responsibility. Callbacks must preserve bounded cursors;
    /// finalization does not recheck them. Emits one selected INPUT/OUTPUT record after processing.
    /// @param id Registered endpoint ID used as the log prefix.
    /// @param descriptor Packed input-only endpoint descriptor.
    /// @param input Input block stream.
    /// @param process Internal callback that consumes and processes one item.
    /// @return output Final encoded response block stream.
    /// @return credit Remaining native-value budget.
    function runPort(
        uint id,
        uint descriptor,
        bytes calldata input,
        function(Execution memory) internal process
    ) internal returns (bytes memory output, uint credit) {
        return runPort(id, descriptor, bytes32(0), input, process);
    }

    /// @notice Attribute a port invocation explicitly; never infer an account from its peer.
    function runPort(
        uint id,
        uint descriptor,
        bytes32 account,
        bytes calldata input,
        function(Execution memory) internal process
    ) internal returns (bytes memory output, uint credit) {
        Execution memory exec;
        exec.account = account;
        exec.openInput(descriptor, msg.value, input);
        while (exec.more()) {
            process(exec);
        }
        output = exec.finish(id, descriptor);
        credit = exec.drainBudget();
    }
}
