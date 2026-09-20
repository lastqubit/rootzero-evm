// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { EventEmitter } from "./Emitter.sol";

/// @notice Records a guardian role action and its resulting state on a host.
abstract contract GuardianEvent is EventEmitter {
    string private constant ABI = "event Guardian(uint indexed host, bytes32 account, uint32 action, uint status)";

    /// @param host Host node ID where the guardian change occurred.
    /// @param account User account ID whose guardian role the action concerns.
    /// @param action Operation that occurred, using the canonical Actions meaning.
    /// The default Host implementation emits Appoint or Dismiss.
    /// @param status Resulting state: zero is inactive, one is active; other nonzero values are active with host-defined meaning.
    /// Emitters must keep the action and resulting state consistent.
    event Guardian(uint indexed host, bytes32 account, uint32 action, uint status);

    constructor() {
        emit EventAbi(ABI);
    }
}
