// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @title ECDSA
/// @notice Minimal ECDSA signature recovery helpers.
library ECDSA {
    /// @dev Upper bound for the `s` component that prevents signature malleability.
    /// Signatures with `s > MALLEABILITY_THRESHOLD` are rejected.
    uint256 internal constant MALLEABILITY_THRESHOLD =
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    /// @notice Compute the Ethereum signed message hash for a 32-byte digest.
    /// Prepends the standard `"\x19Ethereum Signed Message:\n32"` prefix before hashing,
    /// matching the behaviour of `eth_sign` and most wallet signing flows.
    /// @param hash Raw 32-byte message digest.
    /// @return digest Prefixed and re-hashed digest suitable for `ecrecover`.
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32 digest) {
        assembly ("memory-safe") {
            mstore(0x00, "\x19Ethereum Signed Message:\n32")
            mstore(0x1c, hash)
            digest := keccak256(0x00, 0x3c)
        }
    }

    /// @notice Compute the EIP-712 digest for a domain separator and struct hash.
    /// @param domain EIP-712 domain separator.
    /// @param structHash EIP-712 hash of the signed struct.
    /// @return digest `keccak256("\x19\x01" || domain || structHash)`, suitable for `ecrecover`.
    function toTypedDataHash(bytes32 domain, bytes32 structHash) internal pure returns (bytes32 digest) {
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }

    /// @notice Recover the signer address from a calldata ECDSA signature.
    /// Returns `address(0)` on any validation failure rather than reverting,
    /// so callers must check the return value.
    ///
    /// Validation rules:
    /// - Signature must be exactly 65 bytes (`r || s || v`).
    /// - `v` is normalised to 27 or 28 (accepts raw 0/1 as well).
    /// - `s` must not exceed `MALLEABILITY_THRESHOLD`.
    ///
    /// @param hash Message digest to recover from.
    /// @param signature 65-byte ECDSA signature in `r || s || v` layout.
    /// @return signer Recovered signer address, or `address(0)` if invalid.
    function tryRecoverCalldata(bytes32 hash, bytes calldata signature) internal pure returns (address signer) {
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;

        // Read r, s, v directly from calldata to avoid a memory copy.
        assembly ("memory-safe") {
            let offset := signature.offset
            r := calldataload(offset)
            s := calldataload(add(offset, 0x20))
            v := byte(0, calldataload(add(offset, 0x40)))
        }

        if (v < 27) v += 27;
        if (v != 27 && v != 28) return address(0);
        if (uint256(s) > MALLEABILITY_THRESHOLD) return address(0);

        return ecrecover(hash, v, r, s);
    }

    /// @notice Recover the signer address from an EIP-2098 compact signature.
    /// Returns `address(0)` on any validation failure rather than reverting,
    /// so callers must check the return value.
    /// @param hash Message digest to recover from.
    /// @param r Signature `r`.
    /// @param vs Compact signature word: y parity in the top bit, `s` below it.
    /// @return signer Recovered signer address, or `address(0)` if invalid.
    function tryRecoverCompact(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address signer) {
        uint256 s = uint256(vs) & (type(uint256).max >> 1);
        if (s > MALLEABILITY_THRESHOLD) return address(0);

        return ecrecover(hash, uint8(uint256(vs) >> 255) + 27, r, bytes32(s));
    }
}
