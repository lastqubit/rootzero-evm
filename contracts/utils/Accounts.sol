// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Layout} from "./Layout.sol";
import {InvalidAccount} from "./Errors.sol";
import {Ids} from "./Ids.sol";
import {Nodes} from "./Nodes.sol";
import {ensureAddr, isFamily, toLocalBase, toUnspecifiedBase} from "./Utils.sol";

/// @title Accounts
/// @notice Encoding and decoding helpers for 256-bit account identifiers.
///
/// Host accounts use the Host subtype shared with node IDs, under the Account category.
/// Account IDs embed a 4-byte type tag in bits [255:224]:
///   - `Admin`    — chain-local EVM address in bits [159:0]
///   - `User`     — chain-agnostic EVM address in bits [159:0]
/// EVM account encoders leave the middle bits [191:160] zero.
///
/// An opaque account uses `[0x02][Account][subtype][bytes29(hash)]`. The full
/// account identity must be supplied by
/// lookup or witness data when native account metadata is needed.
///
/// The helpers in this library validate and deconstruct structured account IDs.
library Accounts {
    /// @dev 16-bit family tag shared by all EVM-backed account types.
    uint16 constant Family = (uint16(Layout.Evm) << 8) | uint16(Layout.Account);
    /// @dev Full 4-byte type prefix for admin accounts (chain-local EVM address).
    uint32 constant Admin = (uint32(Layout.Evm) << 24) | (uint32(Layout.Account) << 16) | (uint32(Layout.Admin) << 8);
    /// @dev Full 4-byte type prefix for chain-local host accounts.
    uint32 constant Host = (uint32(Layout.Evm) << 24) | (uint32(Layout.Account) << 16) | (uint32(Layout.Host) << 8);
    /// @dev Full 4-byte type prefix for user accounts (chain-agnostic EVM address).
    uint32 constant User = (uint32(Layout.Evm) << 24) | (uint32(Layout.Account) << 16) | (uint32(Layout.User) << 8);

    /// @notice Extract the 4-byte type prefix from an account ID.
    /// @param value Account identifier.
    /// @return Four-byte prefix occupying bits [255:224].
    function prefix(bytes32 value) internal pure returns (uint32) {
        return uint32(uint(value) >> 224);
    }

    /// @notice Check whether `value` has the account category.
    /// @dev Classification only; representation, subtype, flags, and payload are not validated.
    /// @param value Account identifier to classify.
    /// @return True if the category byte is `Layout.Account`; false otherwise, including zero.
    function isAccount(bytes32 value) internal pure returns (bool) {
        return uint8(uint(value) >> 240) == Layout.Account;
    }

    /// @notice Check whether `value` belongs to the EVM account family.
    /// @dev Classification only; does not require a nonzero embedded address.
    /// @param value Account identifier to classify.
    /// @return True if the representation and category match the EVM account family; false otherwise.
    function isEvm(bytes32 value) internal pure returns (bool) {
        return isFamily(uint(value), Family);
    }

    /// @notice Check whether `value` belongs to the opaque account family.
    /// @dev Classification only; subtype and payload are not validated.
    /// @param value Account identifier to classify.
    /// @return True if the representation and category match the opaque account family; false otherwise.
    function isOpaque(bytes32 value) internal pure returns (bool) {
        return Ids.isOpaque(value, Layout.Account);
    }

    /// @notice Check whether `value` has the EVM admin-account prefix.
    /// @dev Classification only; does not require a nonzero embedded address.
    /// @param value Account identifier to classify.
    /// @return True if the four-byte prefix matches `Admin`; false otherwise.
    function isAdmin(bytes32 value) internal pure returns (bool) {
        return prefix(value) == Admin;
    }

    /// @notice Check whether `value` has the EVM host-account prefix.
    /// @dev Classification only; does not validate chain, address, or authorization.
    /// @param value Account identifier to classify.
    /// @return True if the four-byte prefix matches `Host`; false otherwise.
    function isHost(bytes32 value) internal pure returns (bool) {
        return prefix(value) == Host;
    }

    /// @notice Check whether `value` has the EVM user-account prefix.
    /// @dev Classification only; does not require a nonzero embedded address.
    /// @param value Account identifier to classify.
    /// @return True if the four-byte prefix matches `User`; false otherwise.
    function isUser(bytes32 value) internal pure returns (bool) {
        return prefix(value) == User;
    }

    /// @notice Assert that `value` has the account category and return it unchanged.
    /// @dev Reverts with `InvalidAccount` for non-account values, including zero.
    /// Representation, subtype, flags, and payload are not validated.
    /// @param value Account identifier to validate.
    /// @return The same `value` if validation succeeds.
    function account(bytes32 value) internal pure returns (bytes32) {
        if (!isAccount(value)) revert InvalidAccount();
        return value;
    }

    /// @notice Assert that `value` belongs to the EVM account family, contains
    /// a nonzero embedded address, and return it unchanged.
    /// @dev Reverts with `InvalidAccount` for a family mismatch or `ZeroAddress` for a zero address.
    /// @param value Account identifier to validate.
    /// @return The same `value` if validation succeeds.
    function evm(bytes32 value) internal pure returns (bytes32) {
        if (!isFamily(uint(value), Family)) revert InvalidAccount();
        ensureAddr(address(uint160(uint(value))));
        return value;
    }

    /// @notice Assert that `value` is an opaque account and return it unchanged.
    /// @dev Reverts with `InvalidAccount` for a family mismatch; subtype and payload are not validated.
    /// @param value Account identifier to validate.
    /// @return The same `value` if validation succeeds.
    function opaque(bytes32 value) internal pure returns (bytes32) {
        if (!isOpaque(value)) revert InvalidAccount();
        return value;
    }

    /// @notice Assert that `value` is an admin account, contains a nonzero
    /// embedded address, and return it unchanged.
    /// @dev Reverts with `InvalidAccount` for a prefix mismatch or `ZeroAddress` for a zero address.
    /// @param value Account identifier to validate.
    /// @return The same `value` if validation succeeds.
    function admin(bytes32 value) internal pure returns (bytes32) {
        if (uint32(uint(value) >> 224) != Admin) revert InvalidAccount();
        ensureAddr(address(uint160(uint(value))));
        return value;
    }

    /// @notice Assert that `value` is a host account, contains a nonzero
    /// embedded address, and return it unchanged.
    /// @dev Reverts with `InvalidAccount` for a prefix mismatch or `ZeroAddress` for a zero address.
    /// Does not require the current chain or deployed code and does not authorize the account.
    /// @param value Account identifier to validate.
    /// @return The same `value` if validation succeeds.
    function host(bytes32 value) internal pure returns (bytes32) {
        if (!isHost(value)) revert InvalidAccount();
        ensureAddr(address(uint160(uint(value))));
        return value;
    }

    /// @notice Assert that `value` is a user account, contains a nonzero
    /// embedded address, and return it unchanged.
    /// @dev Reverts with `InvalidAccount` for a prefix mismatch or `ZeroAddress` for a zero address.
    /// @param value Account identifier to validate.
    /// @return The same `value` if validation succeeds.
    function user(bytes32 value) internal pure returns (bytes32) {
        if (uint32(uint(value) >> 224) != User) revert InvalidAccount();
        ensureAddr(address(uint160(uint(value))));
        return value;
    }

    /// @notice Assert that `value` is Rootzero (zero) or has the account category and return it unchanged.
    /// @dev Reverts with `InvalidAccount` for nonzero values outside the account category.
    /// Representation, subtype, flags, and payload are not validated; does not authorize the account.
    /// @param value Counterparty identifier to validate.
    /// @return The same `value` if validation succeeds.
    function counterparty(bytes32 value) internal pure returns (bytes32) {
        if (value != bytes32(0) && !isAccount(value)) revert InvalidAccount();
        return value;
    }

    /// @notice Encode an EVM address as a chain-local admin account ID.
    /// @dev Encoding only; use `admin` to validate the embedded address.
    /// @param accountAddr EVM address to embed.
    /// @return Admin account ID bound to the current chain.
    function toAdmin(address accountAddr) internal view returns (bytes32) {
        return bytes32(toLocalBase(Admin) | uint(uint160(accountAddr)));
    }

    /// @notice Encode an EVM address as a chain-local host account ID.
    /// @dev Encoding only; use `host` to validate the embedded address.
    /// @param hostAddr EVM address to embed.
    /// @return Host account ID bound to the current chain.
    function toHost(address hostAddr) internal view returns (bytes32) {
        return bytes32(toLocalBase(Host) | uint(uint160(hostAddr)));
    }

    /// @notice Derive a host account from an EVM host node, preserving its chain and address.
    /// @dev Validates the node prefix via `Nodes.host`. Does not require a local chain or deployed code.
    /// @param node EVM host-node identifier to convert.
    /// @return Host account ID with the node's chain and address.
    function toHost(uint node) internal pure returns (bytes32) {
        node = Nodes.host(node);
        return bytes32((uint(Host) << 224) | (uint(uint32(node >> 192)) << 192) | uint(uint160(node)));
    }

    /// @notice Encode an EVM address as a chain-agnostic user account ID.
    /// @dev Encoding only; use `user` to validate the embedded address.
    /// @param accountAddr EVM address to embed.
    /// @return User account ID without a chain binding.
    function toUser(address accountAddr) internal pure returns (bytes32) {
        return bytes32(toUnspecifiedBase(User) | uint(uint160(accountAddr)));
    }

    /// @notice Derive an opaque account ID from a keccak preimage.
    /// @param preimage Preimage encoded as `0x01 || Account || subtype || payload`.
    /// @return `[0x02][Account][subtype][bytes29(keccak256(preimage))]`.
    function toKeccak(bytes memory preimage) internal pure returns (bytes32) {
        return Ids.toKeccak(Layout.Account, preimage);
    }

    /// @notice Assert that `value` matches the opaque keccak ID for `preimage`.
    /// @param value Opaque account ID to validate.
    /// @param preimage Preimage whose first byte is `0x01`.
    /// @return The same `value` if validation succeeds.
    function matchKeccak(bytes32 value, bytes memory preimage) internal pure returns (bytes32) {
        if (value != Ids.toKeccak(Layout.Account, preimage)) revert InvalidAccount();
        return value;
    }

    /// @notice Extract the address embedded in an EVM-family account ID.
    /// @dev Validates via `evm`; reverts with `InvalidAccount` for a family mismatch
    /// or `ZeroAddress` for a zero embedded address.
    /// @param value EVM-family account ID.
    /// @return Embedded address (bits [159:0] of the ID).
    function addr(bytes32 value) internal pure returns (address) {
        return address(uint160(uint(evm(value))));
    }
}
