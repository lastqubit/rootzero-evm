// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { EventEmitter } from "./Emitter.sol";

/// @notice Records an asset lifecycle or administrative action and its resulting state on a host.
abstract contract AssetEvent is EventEmitter {
    string private constant ABI = "event Asset(uint indexed host, bytes32 asset, uint codes)";

    /// @param host Host node ID where the asset action occurred.
    /// @param asset Asset identifier.
    /// @param codes Packed action/entity-kind/effect/state IDs describing this event, using Activity's codes convention.
    /// Create means the asset was created, independently of its resulting active state.
    /// @dev Up to eight nonzero uint32 IDs, lowest slot first; unused high slots are zero.
    /// Requires exactly one States.Active or States.Inactive code describing the resulting state.
    /// Missing, repeated, or conflicting active/inactive codes violate this event convention.
    /// Emitters enforce the convention; the event declaration does not validate codes.
    /// Other code order and duplicates are preserved; adjacent IDs are not paired.
    event Asset(uint indexed host, bytes32 asset, uint codes);

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
