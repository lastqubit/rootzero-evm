// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @dev Thrown when a caller, account, or node lacks required access.
error AccessDenied();

/// @notice Assert that `msg.sender` equals `expected` and return it.
/// @param expected Address required to be the current message sender.
/// @return The validated sender address.
function enforceSender(address expected) view returns (address) {
    if (msg.sender != expected) revert AccessDenied();
    return expected;
}

/// @title CallerAccess
/// @notice Authorization capability required by command entrypoints.
abstract contract CallerAccess {
    /// @notice Assert that `caller` may invoke a command and return it.
    function enforceCaller(address caller) internal view virtual returns (address);
}

/// @title CommandAccess
/// @notice Authorization capability required by outbound command execution.
abstract contract CommandAccess {
    /// @notice Assert that `command` is a trusted command ID and resolve its EVM endpoint.
    /// @return selector ABI selector encoded by the command ID.
    /// @return target Contract address encoded by the command ID.
    function enforceCommand(uint command) internal view virtual returns (bytes4 selector, address target);
}

/// @title PortAccess
/// @notice Authorization capability required by outbound port calls.
abstract contract PortAccess {
    /// @notice Assert that `port` is a trusted port ID and resolve its EVM endpoint.
    /// @return selector ABI selector encoded by the port ID.
    /// @return target Contract address encoded by the port ID.
    function enforcePort(uint port) internal view virtual returns (bytes4 selector, address target);
}

/// @title PeerAccess
/// @notice Authorization capability required by inbound peer endpoints.
/// @dev Admission grants full trust across the host's port surface. Peers are
/// validated host extensions, not holders of per-operation permissions.
abstract contract PeerAccess {
    /// @notice Assert that `caller` is an authorized peer and return it.
    function enforcePeer(address caller) internal view virtual returns (address);
}

/// @title AdminAccess
/// @notice Authorization capability required by administrative command entrypoints.
abstract contract AdminAccess {
    /// @notice Assert that `account` and `caller` may invoke an administrative command.
    function enforceAdmin(bytes32 account, address caller) internal view virtual returns (bytes32);
}

/// @title NodeAccess
/// @notice Aggregate hook surface required by node administration and guards.
/// Contains declarations only; hosts provide the policy and storage.
abstract contract NodeAccess is PeerAccess, AdminAccess, CommandAccess, PortAccess {
    /// @notice Grant authorization to a node.
    function authorizeNode(uint node) internal virtual;

    /// @notice Revoke authorization from a node.
    function revokeNode(uint node) internal virtual;
}

/// @title GuardianAccess
/// @notice Guardian authorization and mutation capabilities required by guardian features.
/// Contains declarations only; hosts provide the policy and storage.
abstract contract GuardianAccess {
    /// @notice Appoint an account as a guardian.
    function appointGuardian(bytes32 account) internal virtual;

    /// @notice Dismiss an account from its guardian role.
    function dismissGuardian(bytes32 account) internal virtual;

    /// @notice Assert that `caller` is an active guardian and return it.
    function enforceGuardian(address caller) internal view virtual returns (address);
}
