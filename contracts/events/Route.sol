// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {EventEmitter} from "./Emitter.sol";

/// @notice Records a portal route action and its resulting state on a host.
abstract contract RouteEvent is EventEmitter {
    string private constant ABI = "event Route(uint indexed host, uint portal, uint32 action, uint status)";

    /// @param host Host node ID that owns the route.
    /// @param portal Destination portal implementation's host ID.
    /// @param action Operation that occurred, using the canonical Actions meaning.
    /// Add/Remove describe route membership; Enable/Disable toggle a configured route.
    /// @param status Resulting state: zero is inactive, one is active; other nonzero values are active with host-defined meaning.
    /// Emitters must keep the action and resulting state consistent.
    event Route(uint indexed host, uint portal, uint32 action, uint status);

    constructor() {
        emit EventAbi(ABI);
    }
}
