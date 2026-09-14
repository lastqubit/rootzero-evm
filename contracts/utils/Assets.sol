// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Layout} from "./Layout.sol";
import {OutOfRange, InvalidAsset, UnauthorizedAsset, ZeroAmount} from "./Errors.sol";
import {Ids} from "./Ids.sol";
import {ensureAddr, isFamily, matchesBase, toLocalBase} from "./Utils.sol";

/// @title Assets
/// @notice Encoding and decoding helpers for 256-bit asset identifiers.
///
/// Asset IDs embed a 4-byte type tag in bits [255:224]:
///   - `Rootzero` - the singleton global Rootzero asset; no subtype or payload
///   - `ChainAsset` - the chain coin/token; no address payload
///   - `Derived` and `Virtual` - reserved subtypes without dedicated helpers
///   - `Erc20` - ERC-20 token; contract address in bits [159:0]
/// ERC-20 asset encoders leave the middle bits [191:160] zero.
///
/// An opaque asset uses `[0x02][Asset][subtype][bytes29(hash)]`. The full asset
/// metadata must be supplied by
/// lookup or witness data when chain token handling needs it.
///
/// The helpers in this library validate and deconstruct structured asset IDs.
///
/// EVM asset IDs are chain-local and include `block.chainid` in bits [223:192].
/// The Rootzero asset ID is global and leaves the remaining 28 bytes zero.
library Assets {
    /// @dev Complete singleton global Rootzero asset ID `[Rootzero][Asset][0][0]`.
    bytes32 constant Rootzero = bytes32((uint(Layout.Rootzero) << 248) | (uint(Layout.Asset) << 240));
    /// @dev 16-bit family tag shared by all EVM-backed asset types.
    uint16 constant Family = (uint16(Layout.Evm) << 8) | uint16(Layout.Asset);
    /// @dev Full 4-byte type prefix for the chain coin/token asset.
    uint32 constant Chain = (uint32(Layout.Evm) << 24) | (uint32(Layout.Asset) << 16);
    /// @dev Full 4-byte type prefix for ERC-20 assets.
    uint32 constant Erc20 = (uint32(Layout.Evm) << 24) | (uint32(Layout.Asset) << 16) | (uint32(Layout.Erc20) << 8);

    /// @notice Return true if `asset` belongs to the EVM asset family.
    function isEvm(bytes32 asset) internal pure returns (bool) {
        return isFamily(uint(asset), Family);
    }

    /// @notice Return true if `asset` is opaque.
    function isOpaque(bytes32 asset) internal pure returns (bool) {
        return Ids.isOpaque(asset, Layout.Asset);
    }

    /// @notice Return true if `asset` is the singleton global Rootzero asset.
    function isRootzero(bytes32 asset) internal pure returns (bool) {
        return asset == Rootzero;
    }

    /// @notice Return true if `asset` is the local chain coin/token asset.
    function isChain(bytes32 asset) internal view returns (bool) {
        return asset == toChain();
    }

    /// @notice Return true if `asset` is a local ERC-20 asset.
    function isErc20(bytes32 asset) internal view returns (bool) {
        return matchesBase(asset, toLocalBase(Erc20));
    }

    /// @notice Assert that `value` belongs to the EVM asset family and return it unchanged.
    /// @param value Asset identifier to validate.
    /// @return asset The same `value` if it is an EVM asset.
    function evm(bytes32 value) internal pure returns (bytes32 asset) {
        if (!isEvm(value)) revert InvalidAsset();
        return value;
    }

    /// @notice Assert that `value` is an opaque asset and return it unchanged.
    /// @param value Asset identifier to validate.
    /// @return asset The same `value` if it is opaque.
    function opaque(bytes32 value) internal pure returns (bytes32 asset) {
        if (!isOpaque(value)) revert InvalidAsset();
        return value;
    }

    /// @notice Assert that `value` is the global Rootzero asset and return it unchanged.
    /// @param value Asset identifier to validate.
    /// @return asset The same `value` if it is the Rootzero asset.
    function rootzero(bytes32 value) internal pure returns (bytes32 asset) {
        if (!isRootzero(value)) revert InvalidAsset();
        return value;
    }

    /// @notice Assert that `value` is the local chain coin/token asset and return it unchanged.
    /// @param value Asset identifier to validate.
    /// @return asset The same `value` if it is the local chain asset.
    function chain(bytes32 value) internal view returns (bytes32 asset) {
        if (!isChain(value)) revert InvalidAsset();
        return value;
    }

    /// @notice Assert that `value` is a local ERC-20 asset and return it unchanged.
    /// @param value Asset identifier to validate.
    /// @return asset The same `value` if it is a local ERC-20 asset.
    function erc20(bytes32 value) internal view returns (bytes32 asset) {
        if (!isErc20(value)) revert InvalidAsset();
        return value;
    }

    /// @notice Create the chain-local coin/token asset ID.
    /// @return Asset ID for the chain token on the current chain.
    function toChain() internal view returns (bytes32) {
        return bytes32(toLocalBase(Chain));
    }

    /// @notice Create a chain-local ERC-20 asset ID for `addr`.
    /// @param addr ERC-20 token contract address.
    /// @return Asset ID with `addr` embedded in bits [159:0].
    function toErc20(address addr) internal view returns (bytes32) {
        return bytes32(toLocalBase(Erc20) | uint(uint160(addr)));
    }

    /// @notice Derive an opaque asset ID from a keccak preimage.
    /// @param preimage Preimage encoded as `0x01 || Asset || subtype || payload`.
    /// @return asset `[0x02][Asset][subtype][bytes29(keccak256(preimage))]`.
    function toKeccak(bytes memory preimage) internal pure returns (bytes32 asset) {
        return Ids.toKeccak(Layout.Asset, preimage);
    }

    /// @notice Assert that `asset` matches the opaque keccak ID for `preimage`.
    /// @param asset Opaque asset ID to validate.
    /// @param preimage Preimage whose first byte is `0x01`.
    /// @return The same `asset` value if it matches.
    function matchKeccak(bytes32 asset, bytes memory preimage) internal pure returns (bytes32) {
        if (asset != Ids.toKeccak(Layout.Asset, preimage)) revert InvalidAsset();
        return asset;
    }

    /// @notice Extract the ERC-20 contract address from an asset ID.
    /// Reverts if `asset` is not a local ERC-20 asset.
    /// @param asset ERC-20 asset identifier.
    /// @return Token contract address embedded in bits [159:0].
    function erc20Addr(bytes32 asset) internal view returns (address) {
        return ensureAddr(address(uint160(uint(erc20(asset)))));
    }

    /// @notice Assert that `asset` is a local ERC-20 for `token` and return it unchanged.
    /// Reverts if `asset` is not a local ERC-20 asset or if its token address differs.
    /// @param asset ERC-20 asset identifier.
    /// @param token Expected token contract address.
    /// @return The same `asset` value if valid.
    function matchErc20(bytes32 asset, address token) internal view returns (bytes32) {
        if (erc20Addr(asset) != token) revert InvalidAsset();
        return asset;
    }
}

/// @title Amounts
/// @notice Validation helpers for token amounts.
library Amounts {
    /// @notice Assert that `amount` is non-zero and return it unchanged.
    /// @param amount Amount to validate.
    /// @return The same `amount` value if valid.
    function ensure(uint amount) internal pure returns (uint) {
        if (amount == 0) {
            revert ZeroAmount();
        }
        return amount;
    }

    /// @notice Assert that `amount` is within `[min, max]` and return it unchanged.
    /// @param amount Amount to validate.
    /// @param min Inclusive lower bound.
    /// @param max Inclusive upper bound.
    /// @return The same `amount` value if valid.
    function ensure(uint amount, uint min, uint max) internal pure returns (uint) {
        if (amount < min || amount > max) {
            revert OutOfRange();
        }
        return amount;
    }

    /// @notice Clamp `available` to `[min, max]`.
    /// Uses all of `available` if it does not exceed `max`; reverts if the result
    /// would fall below `min`.
    /// @param available Total available balance.
    /// @param min Minimum acceptable resolved amount.
    /// @param max Maximum amount to consume.
    /// @return Clamped amount in `[min, max]`.
    function resolve(uint available, uint min, uint max) internal pure returns (uint) {
        uint amount = available > max ? max : available;
        if (amount < min) {
            revert OutOfRange();
        }
        return amount;
    }
}
