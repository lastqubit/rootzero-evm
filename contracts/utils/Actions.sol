// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @notice Canonical action identifiers used by protocol events.
/// @dev In every event with an action field, the action identifies the operation
/// that occurred. Its canonical meaning is shared across event types; any
/// accompanying state fields describe the result, not a replacement meaning.
/// Codes are grouped in blocks of 16; unassigned values are reserved.
/// These ranges organize the catalog, not permission checks or runtime dispatch.
/// The grouped catalog replaces the numeric assignments used through v1.41.0.
library Actions {
    // Lifecycle and membership: 0-15. Values 8-15 are reserved.
    uint32 constant None = 0;
    uint32 constant Create = 1;
    uint32 constant Update = 2;
    uint32 constant Delete = 3;
    /// @dev Add an existing entity to a set or configuration.
    uint32 constant Add = 4;
    /// @dev Remove an entity from a set or configuration without deleting it.
    uint32 constant Remove = 5;
    uint32 constant Enable = 6;
    uint32 constant Disable = 7;

    // Permissions and roles: 16-31. Values 22-31 are reserved.
    uint32 constant Authorize = 16;
    uint32 constant Revoke = 17;
    uint32 constant Appoint = 18;
    uint32 constant Dismiss = 19;
    uint32 constant Allow = 20;
    uint32 constant Deny = 21;

    // Transfers: 32-47. Values 38-47 are reserved.
    uint32 constant Transfer = 32;
    uint32 constant Payout = 33;
    uint32 constant Deposit = 34;
    uint32 constant Withdraw = 35;
    uint32 constant Cashin = 36;
    uint32 constant Cashout = 37;

    // Supply: 48-63. Values 50-63 are reserved.
    uint32 constant Mint = 48;
    uint32 constant Burn = 49;

    // Accounting and settlement: 64-79. Values 70-79 are reserved.
    uint32 constant Post = 64;
    /// @dev Legacy book-command meaning; historical deployments used code 18.
    uint32 constant Book = 65;
    uint32 constant Realize = 66;
    uint32 constant Settle = 67;
    uint32 constant Fee = 68;
    uint32 constant Refund = 69;

    // Trading and credit: 80-95. Values 84-95 are reserved.
    uint32 constant Swap = 80;
    uint32 constant Borrow = 81;
    uint32 constant Repay = 82;
    uint32 constant Liquidate = 83;

    // Values 96 and above are reserved for future action groups.
}
