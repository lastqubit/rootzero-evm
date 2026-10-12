// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {InvalidId, InvalidPreimage} from "./Errors.sol";
import {Layout} from "./Layout.sol";

/// @title Ids
/// @notice Shared helpers for the protocol-wide 256-bit ID convention.
///
/// Opaque IDs retain the shared category and subtype taxonomy:
///   `[0x02][category][subtype][bytes29 truncated hash]`
///
/// Opaque keccak preimages start with the hash format, category, and subtype,
/// and the ID is derived as:
///   `preimage = 0x01 || category || subtype || payload`
///   `id = 0x02 || category || subtype || bytes29(keccak256(preimage))`
library Ids {
    /// @dev Preimage format/hash tag for keccak256-derived opaque IDs.
    uint8 constant Keccak = 0x01;

    /// @notice Return true if `id` is opaque and carries a nonzero category.
    /// @param id Opaque identifier to inspect.
    /// @return True if `id` is opaque and carries a nonzero category.
    function isOpaque(bytes32 id) internal pure returns (bool) {
        return uint8(uint(id) >> 248) == Layout.Opaque && uint8(uint(id) >> 240) != 0;
    }

    /// @notice Return true if `id` is opaque and carries `category`.
    /// @param id Opaque identifier to inspect.
    /// @param category Expected opaque-ID category byte.
    /// @return True if `id` is opaque and carries `category`.
    function isOpaque(bytes32 id, uint8 category) internal pure returns (bool) {
        return category != 0 && uint16(uint(id) >> 240) == ((uint16(Layout.Opaque) << 8) | uint16(category));
    }

    /// @notice Return true if `id` is opaque and carries `category` and `subtype`.
    /// @param id Opaque identifier to inspect.
    /// @param category Expected opaque-ID category byte.
    /// @param subtype Expected opaque-ID subtype byte.
    /// @return True if `id` is opaque and carries `category` and `subtype`.
    function isOpaque(bytes32 id, uint8 category, uint8 subtype) internal pure returns (bool) {
        return
            category != 0 &&
            uint24(uint(id) >> 232) == ((uint24(Layout.Opaque) << 16) | (uint24(category) << 8) | uint24(subtype));
    }

    /// @notice Assert that `value` is opaque and return it unchanged.
    /// @param value ID to validate.
    /// @return id The same `value` if it is opaque.
    function opaque(bytes32 value) internal pure returns (bytes32 id) {
        if (!isOpaque(value)) revert InvalidId();
        return value;
    }

    /// @notice Derive an opaque ID from a keccak preimage.
    /// @param preimage Preimage encoded as `0x01 || category || subtype || payload`.
    /// @return id `0x02 || category || subtype || bytes29(keccak256(preimage))`.
    function toKeccak(bytes memory preimage) internal pure returns (bytes32 id) {
        if (preimage.length < 3 || uint8(preimage[0]) != Keccak || uint8(preimage[1]) == 0) {
            revert InvalidPreimage();
        }
        return
            bytes32(
                (uint(Layout.Opaque) << 248) |
                    (uint(uint8(preimage[1])) << 240) |
                    (uint(uint8(preimage[2])) << 232) |
                    (uint(keccak256(preimage)) >> 24)
            );
    }

    /// @notice Derive an opaque ID and require its preimage category.
    /// @param category Expected nonzero category byte.
    /// @param preimage Preimage encoded as `0x01 || category || subtype || payload`.
    /// @return id Opaque identifier derived from the validated preimage.
    function toKeccak(uint8 category, bytes memory preimage) internal pure returns (bytes32 id) {
        id = toKeccak(preimage);
        if (!isOpaque(id, category)) revert InvalidPreimage();
    }

    /// @notice Assert that `value` matches the opaque keccak ID for `preimage`.
    /// @param value Opaque ID to validate.
    /// @param preimage Preimage encoded as `0x01 || category || subtype || payload`.
    /// @return id The same `value` if it matches.
    function matchKeccak(bytes32 value, bytes memory preimage) internal pure returns (bytes32 id) {
        if (value != toKeccak(preimage)) revert InvalidId();
        return value;
    }
}
