// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Specs} from "./Specs.sol";

/// @title Headers
/// @notice Uint header constants for exact-size built-in blocks.
/// @dev Derived from Specs so each block layout has a single definition.
/// Headers are right-aligned: key in bits 32-63, payload length in bits 0-31.
/// Deriving each value by shifting Specs right 192 guarantees the upper 192 bits
/// are zero, allowing direct uint comparisons without a cleanup mask.
library Headers {
    /// @dev Right-aligned ACCOUNT key and exact payload length.
    uint constant Account = Specs.Account >> 192;
    /// @dev Right-aligned ASSET key and exact payload length.
    uint constant Asset = Specs.Asset >> 192;
    /// @dev Right-aligned NODE key and exact payload length.
    uint constant Node = Specs.Node >> 192;
    /// @dev Right-aligned ENTITY key and exact payload length.
    uint constant Entity = Specs.Entity >> 192;
    /// @dev Right-aligned STATUS key and exact payload length.
    uint constant Status = Specs.Status >> 192;
    /// @dev Right-aligned ASSET_AMOUNT key and exact payload length.
    uint constant AssetAmount = Specs.AssetAmount >> 192;
    /// @dev Right-aligned AMOUNT key and exact payload length.
    uint constant Amount = Specs.Amount >> 192;
    /// @dev Right-aligned BALANCE key and exact payload length.
    uint constant Balance = Specs.Balance >> 192;
    /// @dev Right-aligned ASSET_LIABILITY key and exact payload length.
    uint constant AssetLiability = Specs.AssetLiability >> 192;
    /// @dev Right-aligned ACCOUNT_ASSET key and exact payload length.
    uint constant AccountAsset = Specs.AccountAsset >> 192;
    /// @dev Right-aligned RECIPIENT key and exact payload length.
    uint constant Recipient = Specs.Recipient >> 192;
    /// @dev Right-aligned ENVELOPE key and exact payload length.
    uint constant Envelope = Specs.Envelope >> 192;
    /// @dev Right-aligned RESOLUTION key and exact payload length.
    uint constant Resolution = Specs.Resolution >> 192;
    /// @dev Right-aligned INTRODUCTION key and exact payload length.
    uint constant Introduction = Specs.Introduction >> 192;
    /// @dev Right-aligned ENDPOINT key and exact payload length.
    uint constant Endpoint = Specs.Endpoint >> 192;
    /// @dev Right-aligned PIPELINE key and exact payload length.
    uint constant Pipeline = Specs.Pipeline >> 192;
    /// @dev Right-aligned ALLOCATION key and exact payload length.
    uint constant Allocation = Specs.Allocation >> 192;
    /// @dev Right-aligned ALLOWANCE key and exact payload length.
    uint constant Allowance = Specs.Allowance >> 192;
    /// @dev Right-aligned CUSTODY key and exact payload length.
    uint constant Custody = Specs.Custody >> 192;
    /// @dev Right-aligned PAYOUT key and exact payload length.
    uint constant Payout = Specs.Payout >> 192;
    /// @dev Right-aligned TRUST key and exact payload length.
    uint constant Trust = Specs.Trust >> 192;
    /// @dev Right-aligned ACCOUNT_BALANCE key and exact payload length.
    uint constant AccountBalance = Specs.AccountBalance >> 192;
    /// @dev Right-aligned ACCOUNT_AMOUNT key and exact payload length.
    uint constant AccountAmount = Specs.AccountAmount >> 192;
    /// @dev Right-aligned HOST_AMOUNT key and exact payload length.
    uint constant HostAmount = Specs.HostAmount >> 192;
    /// @dev Right-aligned HOST_ACCOUNT_ASSET key and exact payload length.
    uint constant HostAccountAsset = Specs.HostAccountAsset >> 192;
    /// @dev Right-aligned LIMITS key and exact payload length.
    uint constant Limits = Specs.Limits >> 192;
    /// @dev Right-aligned BALANCE_CONSTRAINTS key and exact payload length.
    uint constant BalanceConstraints = Specs.BalanceConstraints >> 192;
    /// @dev Right-aligned POSITION_CONSTRAINTS key and exact payload length.
    uint constant PositionConstraints = Specs.PositionConstraints >> 192;
    /// @dev Right-aligned QUOTE_REQUEST key and exact payload length.
    uint constant QuoteRequest = Specs.QuoteRequest >> 192;
    /// @dev Right-aligned QUOTE key and exact payload length.
    uint constant Quote = Specs.Quote >> 192;
    /// @dev Right-aligned POSITION key and exact payload length.
    uint constant Position = Specs.Position >> 192;
    /// @dev Right-aligned BOOKING key and exact payload length.
    uint constant Booking = Specs.Booking >> 192;
    /// @dev Right-aligned HOST_ASSET key and exact payload length.
    uint constant HostAsset = Specs.HostAsset >> 192;
    /// @dev Right-aligned HOST_ACCOUNT_AMOUNT key and exact payload length.
    uint constant HostAccountAmount = Specs.HostAccountAmount >> 192;
}
