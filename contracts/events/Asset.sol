// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { EventEmitter } from "./Emitter.sol";

/// @notice Records an asset lifecycle or administrative action and its resulting state on a host.
abstract contract AssetEvent is EventEmitter {
    string private constant ABI = "event Asset(uint indexed host, bytes32 asset, uint codes, uint status)";

    /// @param host Host node ID where the asset action occurred.
    /// @param asset Asset identifier.
    /// @param codes Packed action/effect IDs describing this event, using Activity's codes convention.
    /// Create means the asset was created, independently of its resulting active state.
    /// @param status Resulting state: zero is inactive, one is active; other nonzero values are active with host-defined meaning.
    /// Emitters must keep the codes and resulting state consistent.
    /// @dev Up to eight nonzero uint32 IDs, lowest slot first; unused high slots are zero.
    /// Zero is empty. Order and duplicates are preserved; adjacent IDs are not paired.
    event Asset(uint indexed host, bytes32 asset, uint codes, uint status);

    constructor() {
        emit EventAbi(ABI);
    }
}

/// @notice Emitted when a host declares the preimage for an opaque asset ID.
abstract contract AssetPreimageEvent is EventEmitter {
    string private constant ABI = "event AssetPreimage(bytes32 indexed asset, bytes preimage)";

    /// @param asset Opaque asset ID `[0x02][Asset][subtype][bytes29(hash(preimage))]`.
    /// @param preimage Canonical preimage used to derive or resolve the opaque asset ID.
    /// The preimage starts with `[formatHash][Asset][subtype]`; `0x01` means keccak256.
    event AssetPreimage(bytes32 indexed asset, bytes preimage);

    constructor() {
        emit EventAbi(ABI);
    }
}
