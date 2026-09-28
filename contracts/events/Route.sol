// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {EventEmitter} from "./Emitter.sol";

/// @notice Records a portal route action and its resulting state on a host.
abstract contract RouteEvent is EventEmitter {
    string private constant ABI = "event Route(uint indexed host, uint portal, uint codes, uint status)";

    /// @param host Host node ID that owns the route.
    /// @param portal Destination portal implementation's host ID.
    /// @param codes Packed action/effect IDs describing this event, using Activity's codes convention.
    /// Add/Remove describe route membership; Enable/Disable toggle a configured route.
    /// @param status Resulting state: zero is inactive, one is active; other nonzero values are active with host-defined meaning.
    /// Emitters must keep the codes and resulting state consistent.
    /// @dev Up to eight nonzero uint32 IDs, lowest slot first; unused high slots are zero.
    /// Zero is empty. Order and duplicates are preserved; adjacent IDs are not paired.
    event Route(uint indexed host, uint portal, uint codes, uint status);

    constructor() {
        emit EventAbi(ABI);
    }
}
