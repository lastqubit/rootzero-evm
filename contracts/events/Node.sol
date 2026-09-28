// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { EventEmitter } from "./Emitter.sol";

/// @notice Records a node action and its resulting authorization state on a host.
abstract contract NodeEvent is EventEmitter {
    string private constant ABI = "event Node(uint indexed host, uint node, uint codes)";

    /// @param host Host node ID where the action occurred.
    /// @param node Node ID that the action concerns.
    /// @param codes Packed action/effect/state IDs describing this event, using Activity's codes convention.
    /// The default Host implementation emits Authorize or Revoke.
    /// @dev Up to eight nonzero uint32 IDs, lowest slot first; unused high slots are zero.
    /// Requires exactly one States.Active or States.Inactive code describing the resulting state.
    /// Missing, repeated, or conflicting active/inactive codes violate this event convention.
    /// Emitters enforce the convention; the event declaration does not validate codes.
    /// Other code order and duplicates are preserved; adjacent IDs are not paired.
    event Node(uint indexed host, uint node, uint codes);

    constructor() {
        emit EventAbi(ABI);
    }
}
