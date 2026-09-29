// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {NotDivisible, ValueOverflow, ZeroAddress} from "./Errors.sol";

// Basis-points denominator: 10_000 BPS == 100.00%.
uint16 constant MAX_BPS = 10_000;

/// @notice Assert that `value` fits in uint8 and return it as uint8.
function max8(uint value) pure returns (uint8) {
    if (value > type(uint8).max) {
        revert ValueOverflow();
    }
    return uint8(value);
}

/// @notice Assert that `value` fits in uint16 and return it as uint16.
function max16(uint value) pure returns (uint16) {
    if (value > type(uint16).max) {
        revert ValueOverflow();
    }
    return uint16(value);
}

/// @notice Assert that `value` fits in uint24 and return it as uint24.
function max24(uint value) pure returns (uint24) {
    if (value > type(uint24).max) {
        revert ValueOverflow();
    }
    return uint24(value);
}

/// @notice Assert that `value` fits in uint32 and return it as uint32.
function max32(uint value) pure returns (uint32) {
    if (value > type(uint32).max) {
        revert ValueOverflow();
    }
    return uint32(value);
}

/// @notice Assert that `value` fits in uint40 and return it as uint40.
function max40(uint value) pure returns (uint40) {
    if (value > type(uint40).max) {
        revert ValueOverflow();
    }
    return uint40(value);
}

/// @notice Assert that `value` fits in uint64 and return it as uint64.
function max64(uint value) pure returns (uint64) {
    if (value > type(uint64).max) {
        revert ValueOverflow();
    }
    return uint64(value);
}

/// @notice Assert that `value` fits in uint96 and return it as uint96.
function max96(uint value) pure returns (uint96) {
    if (value > type(uint96).max) {
        revert ValueOverflow();
    }
    return uint96(value);
}

/// @notice Assert that `value` fits in uint128 and return it as uint128.
function max128(uint value) pure returns (uint128) {
    if (value > type(uint128).max) {
        revert ValueOverflow();
    }
    return uint128(value);
}

/// @notice Assert that `value` fits in uint160 and return it as uint160.
function max160(uint value) pure returns (uint160) {
    if (value > type(uint160).max) {
        revert ValueOverflow();
    }
    return uint160(value);
}

// Packed fields

/// @notice Clear the 8-bit field beginning at `shift`.
function clear8(uint value, uint shift) pure returns (uint) {
    return value & ~(uint(type(uint8).max) << shift);
}

/// @notice Clear the 16-bit field beginning at `shift`.
function clear16(uint value, uint shift) pure returns (uint) {
    return value & ~(uint(type(uint16).max) << shift);
}

/// @notice Clear the 32-bit field beginning at `shift`.
function clear32(uint value, uint shift) pure returns (uint) {
    return value & ~(uint(type(uint32).max) << shift);
}

/// @notice Clear the 64-bit field beginning at `shift`.
function clear64(uint value, uint shift) pure returns (uint) {
    return value & ~(uint(type(uint64).max) << shift);
}

/// @notice Replace the 8-bit field beginning at `shift` with `field`.
/// @dev Reverts when `field` does not fit in 8 bits.
function replace8(uint value, uint shift, uint field) pure returns (uint) {
    return clear8(value, shift) | (uint(max8(field)) << shift);
}

/// @notice Replace the 16-bit field beginning at `shift` with `field`.
/// @dev Reverts when `field` does not fit in 16 bits.
function replace16(uint value, uint shift, uint field) pure returns (uint) {
    return clear16(value, shift) | (uint(max16(field)) << shift);
}

/// @notice Replace the 32-bit field beginning at `shift` with `field`.
/// @dev Reverts when `field` does not fit in 32 bits.
function replace32(uint value, uint shift, uint field) pure returns (uint) {
    return clear32(value, shift) | (uint(max32(field)) << shift);
}

/// @notice Replace the 64-bit field beginning at `shift` with `field`.
/// @dev Reverts when `field` does not fit in 64 bits.
function replace64(uint value, uint shift, uint field) pure returns (uint) {
    return clear64(value, shift) | (uint(max64(field)) << shift);
}

/// @notice Assert that `n` is evenly divisible by `divisor`.
/// No-op when `divisor` is zero.
function divisible(uint n, uint divisor) pure {
    if (divisor != 0 && n % divisor != 0) revert NotDivisible();
}

/// @notice Return `addr` if non-zero, otherwise return `or`.
function addrOr(address addr, address or) pure returns (address) {
    return addr == address(0) ? or : addr;
}

/// @notice Assert that `addr` is non-zero and return it unchanged.
function ensureAddr(address addr) pure returns (address) {
    if (addr == address(0)) revert ZeroAddress();
    return addr;
}

/// @notice Convert a signed integer to its 32-byte two's-complement representation.
function intToBytes32(int value) pure returns (bytes32) {
    return bytes32(uint(value));
}

/// @notice Convert a 32-byte two's-complement representation to a signed integer.
function bytes32ToInt(bytes32 value) pure returns (int) {
    return int(uint(value));
}

/// @notice Convert a null-terminated `bytes32` value to a Solidity string.
/// Stops at the first zero byte and returns only the meaningful prefix.
function bytes32ToString(bytes32 value) pure returns (string memory result) {
    uint len;
    while (len < 32 && value[len] != 0) {
        unchecked {
            ++len;
        }
    }

    result = new string(len);
    assembly ("memory-safe") {
        mstore(add(result, 0x20), value)
    }
}

/// @notice Keccak256-hash a single bytes32 word.
function hash32(bytes32 value) pure returns (bytes32 hash) {
    assembly ("memory-safe") {
        mstore(0x00, value)
        hash := keccak256(0x00, 0x20)
    }
}

/// @notice Build a retry ticket commitment for an account and state payload.
/// @param account Account identifier associated with the retryable payload.
/// @param state Serialized state bytes for the retryable payload.
/// @return ticket Keccak256 hash of `account` and `state`.
function retryTicket(bytes32 account, bytes calldata state) pure returns (bytes32 ticket) {
    return keccak256(abi.encode(account, state));
}

/// @notice Build the chain-local base prefix for a 256-bit ID.
/// Embeds the current `block.chainid` so IDs are not portable across chains.
/// @param prefix Four-byte type tag (e.g. `Nodes.Host`, `Nodes.Command`).
/// @return Base value with the type tag in bits [255:224] and chainid in bits [223:192].
function toLocalBase(uint32 prefix) view returns (uint) {
    return (uint(prefix) << 224) | (uint(max32(block.chainid)) << 192);
}

/// @notice Build a chain-unspecified base prefix (no chainid embedded).
/// Used for IDs that must be portable across chains (e.g. user accounts).
/// @param prefix Four-byte type tag.
/// @return Base value with the type tag in bits [255:224] and zeros elsewhere.
function toUnspecifiedBase(uint32 prefix) pure returns (uint) {
    return uint(prefix) << 224;
}

/// @notice Check whether `value` belongs to the given 16-bit representation/category family.
/// Only tests the top 2 bytes (bits [255:240]); does not check subtype, flags, or chainid.
/// @param value ID to test.
/// @param family Expected family tag.
/// @return True if the top 2 bytes of `value` match `family`.
function isFamily(uint value, uint16 family) pure returns (bool) {
    return uint16(value >> 240) == family;
}

/// @notice Check whether two IDs share the same 64-bit base (type tag + chainid).
/// Used to verify that an ID matches a locally-constructed base without comparing
/// the lower 192-bit payload.
/// @param value ID to test.
/// @param base Reference base value produced by `toLocalBase`.
/// @return True if bits [255:192] of `value` equal those of `base`.
function matchesBase(bytes32 value, uint base) pure returns (bool) {
    return uint64(uint(value) >> 192) == uint64(base >> 192);
}

/// @notice Apply a basis-points fee to an amount (round down).
/// @param amount Base amount.
/// @param bps Fee rate in basis points (0–10_000).
/// @return `amount * bps / 10_000`, or 0 if either input is zero.
function applyBps(uint amount, uint16 bps) pure returns (uint) {
    if (amount == 0 || bps == 0) return 0;
    return (amount * bps) / MAX_BPS;
}

/// @notice Compute the pre-fee amount given a post-fee amount and a basis-points rate.
/// Useful for back-calculating how much to charge so that the net result equals `amount`.
/// @param amount Desired post-fee (net) amount.
/// @param bps Fee rate in basis points.
/// @return `amount * 10_000 / (10_000 + bps)`, or 0 if either input is zero.
function beforeBps(uint amount, uint16 bps) pure returns (uint) {
    if (amount == 0 || bps == 0) return 0;
    return (amount * MAX_BPS) / (MAX_BPS + bps);
}
