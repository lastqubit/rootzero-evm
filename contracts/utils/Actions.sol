// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @notice Canonical action identifiers used by protocol events.
/// @dev In every event with a codes field, each action identifies an operation
/// that occurred. Its canonical meaning is shared across event types; any
/// accompanying state fields describe the result, not a replacement meaning.
/// Codes are grouped in blocks of 16; unassigned values are reserved.
/// These ranges organize the catalog, not permission checks or runtime dispatch.
/// The grouped catalog replaces the numeric assignments used through v1.41.0.
/// Actions occupy category 0 (0x00000000-0x1fffffff) of eight possible categories.
/// The top three bits select the category; the remaining 29 bits identify the code.
/// Every codes field packs up to eight action, entity-kind, effect, or state IDs, lowest uint32 slot first.
/// Entries are contiguous and nonzero, with zero padding in unused high slots.
/// None denotes an empty list; identifiers are not bit flags.
/// @dev Constants use uint for composition; each identifier must still fit one uint32 slot.
library Actions {
    // Lifecycle and membership: 0-15. Values 8-15 are reserved.
    uint constant None = 0;
    uint constant Create = 1;
    uint constant Update = 2;
    uint constant Delete = 3;
    /// @dev Add an existing entity to a set or configuration.
    uint constant Add = 4;
    /// @dev Remove an entity from a set or configuration without deleting it.
    uint constant Remove = 5;
    uint constant Enable = 6;
    uint constant Disable = 7;

    // Permissions and roles: 16-31. Values 22-31 are reserved.
    uint constant Authorize = 16;
    uint constant Revoke = 17;
    uint constant Appoint = 18;
    uint constant Dismiss = 19;
    uint constant Allow = 20;
    uint constant Deny = 21;

    // Transfers: 32-47. Values 38-47 are reserved.
    uint constant Transfer = 32;
    uint constant Payout = 33;
    uint constant Deposit = 34;
    uint constant Withdraw = 35;
    uint constant Cashin = 36;
    uint constant Cashout = 37;

    // Supply: 48-63. Values 50-63 are reserved.
    uint constant Mint = 48;
    uint constant Burn = 49;

    // Accounting and settlement: 64-79. Values 70-79 are reserved.
    uint constant Post = 64;
    /// @dev Legacy book-command meaning; historical deployments used code 18.
    uint constant Book = 65;
    uint constant Realize = 66;
    uint constant Settle = 67;
    uint constant Fee = 68;
    uint constant Refund = 69;

    // Trading and credit: 80-95. Values 84-95 are reserved.
    uint constant Swap = 80;
    uint constant Borrow = 81;
    uint constant Repay = 82;
    uint constant Liquidate = 83;

    // Values 96-0x1fffffff are reserved for future action groups.
}
