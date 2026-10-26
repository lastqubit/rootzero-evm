// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Assets} from "../utils/Assets.sol";
import {INVALID_BLOCK} from "../utils/Errors.sol";

/// @dev Thrown when an ID is not trusted by the commander's registry.
/// @param id The first untrusted ID.
error Untrusted(bytes32 id);

/// @dev Right-aligned Untrusted(bytes32) selector for direct assembly use.
uint constant UNTRUSTED = 0x34c1e061;

/// @dev Right-aligned `checkTrust()` selector: the raw registry check entrypoint.
uint constant TRUST_CHECK = 0x131d5b28;

/// @dev The global Rootzero asset ID (`Assets.Rootzero`) as a literal for assembly. It and the
/// chain asset are always trusted: checks skip their storage read and the registry rejects them.
uint constant ROOTZERO_ASSET = 0x0103000000000000000000000000000000000000000000000000000000000000;

/// @dev Storage salt: an ID's trust flag lives at slot `id ^ TRUST_SALT`,
/// avoiding a mapping hash per lookup. keccak256("rootzero.trust").
uint constant TRUST_SALT = 0x07c06564bba79277332e68c118f927435830a5f10d6b54ba4e54063da43584a3;

/// @title TrustSlots
/// @notice Salted direct storage for a host's trusted IDs.
/// @dev One slot per ID, keyed by `id ^ TRUST_SALT`. IDs are self-describing, so
/// nodes, assets, accounts and other entities share one set without collisions.
library TrustSlots {
    /// @notice Return whether `id` is trusted.
    /// @param id Trusted-set identifier of any kind.
    /// @return trusted Whether the ID is in the set.
    function get(uint id) internal view returns (bool trusted) {
        assembly ("memory-safe") {
            trusted := sload(xor(id, TRUST_SALT))
        }
    }

    /// @notice Set whether `id` is trusted.
    /// @param id Trusted-set identifier of any kind.
    /// @param trusted Whether the ID should be in the set.
    function set(uint id, bool trusted) internal {
        assembly ("memory-safe") {
            sstore(xor(id, TRUST_SALT), trusted)
        }
    }
}

/// @dev Storage salt: an account's guardian flag lives at slot `account ^ GUARDIAN_SALT`,
/// separate from the trusted set. keccak256("rootzero.guardian").
uint constant GUARDIAN_SALT = 0x43be011033770cfe1eed2b685ae7ccb1fc8b006904ab088a9ddee9a860a259e3;

/// @title GuardianSlots
/// @notice Salted direct storage for a host's active guardian accounts.
/// @dev Mirrors TrustSlots with its own salt, so guardian roles never share a slot with
/// trusted IDs: endorsing an account cannot make it a guardian.
library GuardianSlots {
    /// @notice Return whether `account` is an active guardian.
    /// @param account User account identifier.
    /// @return active Whether the account holds the guardian role.
    function get(bytes32 account) internal view returns (bool active) {
        assembly ("memory-safe") {
            active := sload(xor(account, GUARDIAN_SALT))
        }
    }

    /// @notice Set whether `account` is an active guardian.
    /// @param account User account identifier.
    /// @param active Whether the account should hold the guardian role.
    function set(bytes32 account, bool active) internal {
        assembly ("memory-safe") {
            sstore(xor(account, GUARDIAN_SALT), active)
        }
    }
}

/// @title TrustRegistry
/// @notice Raw entrypoint through which hosts check IDs against this host's trusted set.
/// @dev Opt-in mixin for commanders. Hosts call it with `Runtime.requireTrusted`.
/// The chain asset and the Rootzero asset are always trusted without a storage read.
abstract contract TrustRegistry {
    /// @notice Revert unless every ID is trusted.
    /// @dev Non-ABI calldata: the `checkTrust()` selector followed by packed 32-byte IDs.
    /// Returns no data. Reverts `Untrusted(id)` for the first untrusted ID and
    /// `InvalidBlock` unless the IDs are whole words. Native assets always pass.
    function checkTrust() external view {
        bytes32 chain = Assets.toChain();
        assembly ("memory-safe") {
            if mod(sub(calldatasize(), 4), 32) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            for { let p := 4 } lt(p, calldatasize()) { p := add(p, 32) } {
                let id := calldataload(p)
                // Native assets are always trusted; only other IDs read their slot.
                if iszero(or(eq(id, chain), eq(id, ROOTZERO_ASSET))) {
                    if iszero(sload(xor(id, TRUST_SALT))) {
                        mstore(0, shl(224, UNTRUSTED))
                        mstore(4, id)
                        revert(0, 36)
                    }
                }
            }
        }
    }
}
