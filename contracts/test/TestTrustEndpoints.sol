// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host, TrustRegistry, TrustSlots} from "../Core.sol";
import {EndorsePort, UnendorsePort} from "../Endpoints.sol";

/// @dev Commander-like host exposing the trust registry, endorsement ports and admin trust commands.
contract TestTrustEndpoints is Host, EndorsePort, UnendorsePort, TrustRegistry {
    constructor(uint commander, uint peer) Host(commander, "TestTrustEndpoints", address(0)) { setTrust(peer, true); }

    function isTrusted(uint id) external view returns (bool) { return TrustSlots.get(id); }

    /// @dev Host-side check through Runtime against this host's commander.
    function requireOne(bytes32 id) external view { requireTrusted(id); }

    /// @dev Host-side batch check with IDs copied to memory first.
    function requireMany(bytes32[] calldata ids) external view {
        bytes32[] memory copy = ids;
        uint ptr;
        assembly ("memory-safe") {
            ptr := add(copy, 32)
        }
        requireTrusted(ptr, ids.length);
    }
}
