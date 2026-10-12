// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { ECDSA } from "../utils/ECDSA.sol";

/// @title Validator
/// @notice ECDSA proof verification with nonce-based replay protection.
/// Proofs use the layout `[bytes20 signer][bytes65 sig]` (85 bytes total).
/// Each (signer, nonce) pair may only be used once; subsequent uses revert.
abstract contract Validator {
    using ECDSA for bytes32;

    /// @dev Thrown when the proof is not exactly 85 bytes.
    error InvalidProof();
    /// @dev Thrown when the recovered signer does not match the claimed signer in the proof.
    error InvalidSigner();
    /// @dev Thrown when the (signer, nonce) pair has already been used.
    error InvalidNonce();

    /// @dev signer address → nonce key → use count (0 = unused, 1+ = used).
    mapping(address account => mapping(uint192 key => uint64)) internal nonces;

    /// @dev Recover the signer from an Ethereum signed message hash and signature.
    /// @param hash Message hash before the Ethereum signed-message prefix is applied.
    /// @param sig ECDSA signature bytes.
    /// @return Recovered signer address, or zero if recovery fails.
    function recover(bytes32 hash, bytes calldata sig) private pure returns (address) {
        return hash.toEthSignedMessageHash().tryRecoverCalldata(sig);
    }

    /// @notice Verify an 85-byte proof against a message hash and nonce.
    /// Proof layout: `[bytes20 signer][bytes65 sig]`.
    /// Increments the (signer, nonce) counter to prevent replay.
    /// @param hash Message hash that was signed.
    /// @param nonce 192-bit nonce key (typically derived from a deadline or sequence number).
    /// @param proof 85-byte proof: 20-byte signer address followed by a 65-byte ECDSA signature.
    /// @return Verified signer address.
    function verify(bytes32 hash, uint192 nonce, bytes calldata proof) internal returns (address) {
        if (proof.length != 85) revert InvalidProof();

        address account = address(bytes20(proof[0:20]));
        address signer = recover(hash, proof[20:]);

        if (account == address(0) || signer != account) revert InvalidSigner();
        if (nonces[account][nonce]++ != 0) revert InvalidNonce();

        return account;
    }
}
