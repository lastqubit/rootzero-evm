// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {EventEmitter} from "./Emitter.sol";

/// @notice Identifies an account activity whose effects are described by other events.
abstract contract ActivityEvent is EventEmitter {
    string private constant ABI = "event Activity(bytes32 indexed account, uint codes, uint id)";

    /// @dev Codes holds up to eight uint32 action, effect, or state IDs, lowest slot first.
    /// Entries are contiguous and nonzero; unused high slots are zero. Zero is an empty list.
    /// Order and duplicates are preserved; adjacency does not imply action-to-effect pairing.
    /// The top three bits of each ID select one of eight categories (id >> 29).
    /// Category 0 is Actions, 4 is Effects, and 5 is States; the other five are reserved.
    /// Constants include their category bits, so a single constant can be passed directly.
    /// @param account Account performing the activity.
    /// @param codes Packed identifiers from `Actions`, `Effects`, and `States`.
    /// @param id Correlation identifier, or zero when no identifier is assigned.
    /// Nonzero identifiers should be unique within the emitting contract on a chain.
    event Activity(bytes32 indexed account, uint codes, uint id);

    constructor() {
        emit EventAbi(ABI);
    }
}
