// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {EventEmitter} from "./Emitter.sol";

/// @notice Identifies an account action whose effects are described by other events.
abstract contract ActionEvent is EventEmitter {
    string private constant ABI = "event Action(bytes32 indexed account, uint32 action)";

    /// @param account Account performing the action.
    /// @param action Semantic action identifier from `Actions`.
    event Action(bytes32 indexed account, uint32 action);

    constructor() {
        emit EventAbi(ABI);
    }
}
