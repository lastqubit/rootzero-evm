// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @title Layout
/// @notice Single-byte and two-byte tag constants that describe the encoding
/// layout of 256-bit IDs used throughout the rootzero protocol.
///
/// IDs are structured as:
///   `[uint32 type][uint32 chainid][192-bit payload]`
/// where `type` is `[uint8 representation][uint8 category][uint8 subtype][uint8 flags]`.
/// Embedded EVM addresses occupy bits [159:0]. The middle bits [191:160]
/// hold the selector for callable nodes and are zero in account and ERC-20 encodings.
///
/// Representation `Opaque` IDs use
/// `[0x02][category][subtype][bytes29 truncated hash]` and require lookup or
/// witness data when the native preimage is needed. `0x00` is reserved for the
/// null/unset ID.
/// Opaque preimages start with `[format/hash][category][subtype]`. `0x01` means
/// the ID hash is keccak256; remaining bytes are host/domain-specific.
library Layout {
    // -------------------------------------------------------------------------
    // Representation tags (first byte of the ID type field)
    // -------------------------------------------------------------------------

    /// @dev Rootzero-native structured ID.
    uint8 constant Rootzero = 0x01;
    /// @dev Opaque hash-backed ID; category and subtype follow this byte, then a 29-byte hash.
    uint8 constant Opaque = 0x02;
    /// @dev EVM-compatible ID; lower 20 payload bytes hold an address when present.
    uint8 constant Evm = 0x03;

    // -------------------------------------------------------------------------
    // Category tags (uint8, second byte of the ID type field)
    // -------------------------------------------------------------------------

    /// @dev ID encodes an account.
    uint8 constant Account = 0x01;
    /// @dev ID encodes a network node (host, command, port, query, or guard).
    uint8 constant Node = 0x02;
    /// @dev ID encodes an asset.
    uint8 constant Asset = 0x03;

    // -------------------------------------------------------------------------
    // Account subtype tags (uint8, third byte of the ID type field)
    // -------------------------------------------------------------------------

    /// @dev Admin account — chain-local, backed by an EVM address.
    uint8 constant Admin = 0x01;
    /// @dev User account — chain-agnostic, backed by an EVM address.
    uint8 constant User = 0x03;
    // -------------------------------------------------------------------------
    // Node subtype tags (uint8, third byte of the ID type field)
    // -------------------------------------------------------------------------

    /// @dev Node is a chain/domain identifier.
    uint8 constant Chain = 0x01;
    /// @dev Shared subtype: a host node under Node, or a host account under Account.
    uint8 constant Host = 0x02;
    /// @dev Node is a command contract.
    uint8 constant Command = 0x03;
    /// @dev Node is a port callable by trusted peer hosts.
    uint8 constant Port = 0x04;
    /// @dev Node is a query contract.
    uint8 constant Query = 0x05;
    /// @dev Node is a guardian-only direct action.
    uint8 constant Guard = 0x06;

    // -------------------------------------------------------------------------
    // Asset subtype tags (uint8, third byte of the ID type field)
    // -------------------------------------------------------------------------

    /// @dev Reserved derived asset subtype; no dedicated helpers.
    uint8 constant Derived = 0x01;
    /// @dev Virtual asset whose realization is defined by its host or application.
    uint8 constant Virtual = 0x02;
    /// @dev ERC-20 fungible token; lower 20 bytes of the ID hold the contract address.
    uint8 constant Erc20 = 0x03;
}
