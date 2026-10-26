// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {PortBase} from "./Base.sol";
import {Specs} from "../Codec.sol";
import {AccessDenied, TrustAccess} from "../core/Access.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Layout} from "../utils/Layout.sol";

using Executions for Execution;

/// @dev Reject node IDs: peers may endorse entities but never grant node authority.
/// @param id ID decoded from peer input.
/// @return The same ID when its category is not Node.
function endorsable(uint id) pure returns (uint) {
    if (uint8(id >> 240) == Layout.Node) revert AccessDenied();
    return id;
}

/// @title EndorsePort
/// @notice Port through which trusted peers add non-node IDs to the host's trusted set.
/// @dev On a commander this lets authorized hosts register entities they create, such as
/// new assets, in the global registry. Node IDs revert AccessDenied.
abstract contract EndorsePort is TrustAccess, PortBase {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = port("portEndorse", Specs.Entity, Specs.Empty, Logs.Input);
    }

    /// @notice Trust each ENTITY block supplied by a trusted peer.
    /// @dev Hints callers to record the complete INPUT batch.
    /// @param data ENTITY block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portEndorse(bytes calldata data) external onlyPeer returns (bytes memory, uint) {
        return runPort(descriptor, data, portEndorseOne);
    }

    /// @dev Process one ENTITY item for the EndorsePort endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function portEndorseOne(Execution memory exec) private {
        setTrust(endorsable(exec.unpackEntity()), true);
    }
}

/// @title UnendorsePort
/// @notice Port through which trusted peers remove non-node IDs from the host's trusted set.
/// @dev Any non-node ID may be removed; admins and guardians can restore or revoke.
/// Node IDs revert AccessDenied.
abstract contract UnendorsePort is TrustAccess, PortBase {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = port("portUnendorse", Specs.Entity, Specs.Empty, Logs.Input);
    }

    /// @notice Untrust each ENTITY block supplied by a trusted peer.
    /// @dev Hints callers to record the complete INPUT batch.
    /// @param data ENTITY block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portUnendorse(bytes calldata data) external onlyPeer returns (bytes memory, uint) {
        return runPort(descriptor, data, portUnendorseOne);
    }

    /// @dev Process one ENTITY item for the UnendorsePort endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function portUnendorseOne(Execution memory exec) private {
        setTrust(endorsable(exec.unpackEntity()), false);
    }
}
