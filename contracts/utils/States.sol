// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @notice Canonical state identifiers describing a resulting condition.
/// @dev Event codes fields pack up to eight uint32 IDs into a uint, lowest slot first.
/// States occupy category 5 (0xa0000000-0xbfffffff) of eight possible categories.
/// Constants include the top three category bits and can be passed directly as codes.
/// Zero means no codes or unused high slots; it never means inactive.
/// Codes are grouped in blocks of 16; unassigned values are reserved.
/// These identifiers are not bit flags. Each consumer defines which states apply;
/// Asset, Route, and scoped host access logs require exactly one Active or Inactive code.
/// @dev Constants use uint for composition; each identifier must still fit one uint32 slot.
library States {
    // Activity state: 0xa0000000-0xa000000f. Values after Active are reserved.
    /// @dev The subject is inactive.
    uint constant Inactive = 0xa0000000;
    /// @dev The subject is active.
    uint constant Active = 0xa0000001;

    // Resolution state: 0xa0000010-0xa000001f. Values after Resolved are reserved.
    /// @dev A message digest is retained under its recovery key.
    uint constant Unresolved = 0xa0000010;
    /// @dev The matching recovery record has been consumed.
    uint constant Resolved = 0xa0000011;

    // Values 0xa0000020-0xbfffffff are reserved for future state groups.
}
