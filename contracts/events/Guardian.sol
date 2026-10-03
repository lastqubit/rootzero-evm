// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { EventEmitter } from "./Emitter.sol";

/// @notice Records a guardian role action and its resulting state on a host.
abstract contract GuardianEvent is EventEmitter {
    string private constant ABI = "event Guardian(uint indexed host, bytes32 account, uint codes)";

    /// @param host Host node ID where the guardian change occurred.
    /// @param account User account ID whose guardian role the action concerns.
    /// @param codes Packed action/entity-kind/effect/state IDs describing this event, using Activity's codes convention.
    /// The default Host implementation emits Appoint or Dismiss.
    /// @dev Up to eight nonzero uint32 IDs, lowest slot first; unused high slots are zero.
    /// Requires exactly one States.Active or States.Inactive code describing the resulting state.
    /// Missing, repeated, or conflicting active/inactive codes violate this event convention.
    /// Emitters enforce the convention; the event declaration does not validate codes.
    /// Other code order and duplicates are preserved; adjacent IDs are not paired.
    event Guardian(uint indexed host, bytes32 account, uint codes);

    constructor() {
        emit EventAbi(ABI);
    }
}
