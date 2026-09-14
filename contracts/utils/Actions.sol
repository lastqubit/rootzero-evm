// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @notice Canonical action identifiers used by protocol events.
library Actions {
    uint32 constant None = 0;
    uint32 constant Transfer = 1;
    uint32 constant Payout = 2;
    uint32 constant Settle = 3;
    uint32 constant Deposit = 4;
    uint32 constant Withdraw = 5;
    uint32 constant Fee = 6;
    uint32 constant Mint = 7;
    uint32 constant Burn = 8;
    uint32 constant Swap = 9;
    uint32 constant Borrow = 10;
    uint32 constant Repay = 11;
    uint32 constant Liquidate = 12;
    uint32 constant Refund = 13;
    uint32 constant Post = 14;
    uint32 constant Cashout = 15;
    uint32 constant Cashin = 16;
    uint32 constant Realize = 17;
    /// @dev Historical book-command action; retained for event decoding.
    uint32 constant Book = 18;
}
