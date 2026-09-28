// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { EventEmitter } from "./Emitter.sol";

/// @notice Emitted when an account locks an asset in a protocol operation.
abstract contract LockedEvent is EventEmitter {
    string private constant ABI = "event Locked(bytes32 indexed account, bytes32 asset, uint amount, uint codes)";

    /// @param account Account identifier that locked the asset.
    /// @param asset Asset identifier.
    /// @param amount Amount locked.
    /// @param codes Packed action/effect/state IDs describing this event, using Activity's codes convention.
    /// @dev Up to eight nonzero uint32 IDs, lowest slot first; unused high slots are zero.
    /// Zero is empty. Order and duplicates are preserved; adjacent IDs are not paired.
    event Locked(bytes32 indexed account, bytes32 asset, uint amount, uint codes);

    constructor() {
        emit EventAbi(ABI);
    }
}
