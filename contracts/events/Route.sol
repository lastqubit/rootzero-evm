// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {EventEmitter} from "./Emitter.sol";

/// @notice Records a portal route action and its resulting state on a host.
abstract contract RouteEvent is EventEmitter {
    string private constant ABI = "event Route(uint indexed host, uint portal, uint codes)";

    /// @param host Host node ID that owns the route.
    /// @param portal Destination portal implementation's host ID.
    /// @param codes Packed action/effect/state IDs describing this event, using Activity's codes convention.
    /// Add/Remove describe route membership; Enable/Disable toggle a configured route.
    /// @dev Up to eight nonzero uint32 IDs, lowest slot first; unused high slots are zero.
    /// Requires exactly one States.Active or States.Inactive code describing the resulting state.
    /// Missing, repeated, or conflicting active/inactive codes violate this event convention.
    /// Emitters enforce the convention; the event declaration does not validate codes.
    /// Other code order and duplicates are preserved; adjacent IDs are not paired.
    event Route(uint indexed host, uint portal, uint codes);

    constructor() {
        emit EventAbi(ABI);
    }
}
