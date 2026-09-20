// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { EventEmitter } from "./Emitter.sol";

/// @notice Records a node action and its resulting authorization state on a host.
abstract contract NodeEvent is EventEmitter {
    string private constant ABI = "event Node(uint indexed host, uint node, uint32 action, uint status)";

    /// @param host Host node ID where the action occurred.
    /// @param node Node ID that the action concerns.
    /// @param action Operation that occurred, using the canonical Actions meaning.
    /// The default Host implementation emits Authorize or Revoke.
    /// @param status Resulting state: zero is inactive, one is active; other nonzero values are active with host-defined meaning.
    /// Emitters must keep the action and resulting state consistent.
    event Node(uint indexed host, uint node, uint32 action, uint status);

    constructor() {
        emit EventAbi(ABI);
    }
}
