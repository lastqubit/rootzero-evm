// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { EventEmitter } from "./Emitter.sol";

/// @notice Records a node action and its resulting authorization state on a host.
abstract contract NodeEvent is EventEmitter {
    string private constant ABI = "event Node(uint indexed host, uint node, uint codes, uint status)";

    /// @param host Host node ID where the action occurred.
    /// @param node Node ID that the action concerns.
    /// @param codes Packed action/effect IDs describing this event, using Activity's codes convention.
    /// The default Host implementation emits Authorize or Revoke.
    /// @param status Resulting state: zero is inactive, one is active; other nonzero values are active with host-defined meaning.
    /// Emitters must keep the codes and resulting state consistent.
    /// @dev Up to eight nonzero uint32 IDs, lowest slot first; unused high slots are zero.
    /// Zero is empty. Order and duplicates are preserved; adjacent IDs are not paired.
    event Node(uint indexed host, uint node, uint codes, uint status);

    constructor() {
        emit EventAbi(ABI);
    }
}
