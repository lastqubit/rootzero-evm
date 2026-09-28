// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @notice Canonical effect identifiers describing what happened to an account's assets.
/// @dev Event codes fields pack up to eight uint32 IDs into a uint, lowest slot first.
/// Effects occupy category 4 (0x80000000-0x9fffffff) of eight possible categories.
/// Constants include the top three category bits and can be passed directly as codes.
/// Zero denotes an empty list or unused high slots, not an effect identifier.
/// Codes are grouped in blocks of 16; unassigned values are reserved.
/// These identifiers are not bit flags. Actions describe operations; effects describe outcomes.
library Effects {
    // Asset movement and custody: 0x80000000-0x8000000f. Values after Unlock are reserved.
    /// @dev The account spent an asset.
    uint32 constant Spend = 0x80000000;
    /// @dev The account received an asset.
    uint32 constant Receive = 0x80000001;
    /// @dev An asset was locked for the account.
    uint32 constant Lock = 0x80000002;
    /// @dev An asset was unlocked for the account.
    uint32 constant Unlock = 0x80000003;

    // Values 0x80000010-0x9fffffff are reserved for future effect groups.
}
