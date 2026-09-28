// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { EventEmitter } from "./Emitter.sol";

/// @notice Records a guardian role action and its resulting state on a host.
abstract contract GuardianEvent is EventEmitter {
    string private constant ABI = "event Guardian(uint indexed host, bytes32 account, uint codes, uint status)";

    /// @param host Host node ID where the guardian change occurred.
    /// @param account User account ID whose guardian role the action concerns.
    /// @param codes Packed action/effect IDs describing this event, using Activity's codes convention.
    /// The default Host implementation emits Appoint or Dismiss.
    /// @param status Resulting state: zero is inactive, one is active; other nonzero values are active with host-defined meaning.
    /// Emitters must keep the codes and resulting state consistent.
    /// @dev Up to eight nonzero uint32 IDs, lowest slot first; unused high slots are zero.
    /// Zero is empty. Order and duplicates are preserved; adjacent IDs are not paired.
    event Guardian(uint indexed host, bytes32 account, uint codes, uint status);

    constructor() {
        emit EventAbi(ABI);
    }
}
