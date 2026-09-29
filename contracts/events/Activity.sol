// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {EventEmitter} from "./Emitter.sol";

/// @notice Records an account activity directly or references details in companion events.
abstract contract ActivityEvent is EventEmitter {
    string private constant ABI = "event Activity(bytes32 indexed account, bytes32 subject, uint value, uint codes)";

    /// @dev Codes holds up to eight uint32 action, effect, or state IDs, lowest slot first.
    /// Entries are contiguous and nonzero; unused high slots are zero. Zero is an empty list.
    /// Order and duplicates are preserved; adjacency does not imply action-to-effect pairing.
    /// The top three bits of each ID select one of eight categories (id >> 29).
    /// Category 0 is Actions, 4 is Effects, and 5 is States; the other five are reserved.
    /// Constants include their category bits, so a single constant can be passed directly.
    /// @param account Account performing the activity.
    /// @param subject Asset or other identifier the activity concerns; zero when unused.
    /// @param value Amount, correlation identifier, or other value defined by the emitter's schema.
    /// @dev Codes and the documented emitter schema must distinguish amounts from references.
    /// Direct asset flows use subject as the asset and value as the amount, with the matching
    /// Effects.Spend, Receive, Lock, or Unlock code. References can link companion events
    /// describing assets, amounts, and other details. Only in reference mode, zero means no
    /// identifier; nonzero IDs should be unique within the emitting contract on a chain.
    /// @param codes Packed identifiers from `Actions`, `Effects`, and `States`.
    event Activity(bytes32 indexed account, bytes32 subject, uint value, uint codes);

    constructor() {
        emit EventAbi(ABI);
    }
}
