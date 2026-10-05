// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {PreviousSpecs as HistoricalSpecs} from "./PreviousSpecs.sol";

import {Specs} from "../codec/Specs.sol";

// Frozen uint64 constants for historical codec comparisons only.
/// @notice Right-aligned eight-byte headers for exact-size built-in blocks.
/// @dev High 32 bits contain the key; low 32 bits contain the payload length.
/// Derived from Specs so each block layout has a single definition.
library LegacyHeaders {
    uint64 constant Account = uint64(Specs.Account >> 192);
    uint64 constant Asset = uint64(Specs.Asset >> 192);
    uint64 constant Node = uint64(Specs.Node >> 192);
    uint64 constant Status = uint64(Specs.Status >> 192);
    uint64 constant AssetAmount = uint64(Specs.AssetAmount >> 192);
    uint64 constant Balance = uint64(Specs.Balance >> 192);
    uint64 constant AssetLiability = uint64(Specs.AssetLiability >> 192);
    uint64 constant AccountAsset = uint64(Specs.AccountAsset >> 192);
    uint64 constant Bootstrap = uint64(HistoricalSpecs.Bootstrap >> 192);
    uint64 constant Allocation = uint64(Specs.Allocation >> 192);
    uint64 constant Allowance = uint64(Specs.Allowance >> 192);
    uint64 constant Custody = uint64(Specs.Custody >> 192);
    uint64 constant AccountAmount = uint64(Specs.AccountAmount >> 192);
    uint64 constant HostAmount = uint64(Specs.HostAmount >> 192);
    uint64 constant HostAccountAsset = uint64(Specs.HostAccountAsset >> 192);
    uint64 constant Limits = uint64(Specs.Limits >> 192);
    uint64 constant BalanceConstraints = uint64(Specs.BalanceConstraints >> 192);
    uint64 constant PositionConstraints = uint64(Specs.PositionConstraints >> 192);
    uint64 constant Quote = uint64(Specs.Quote >> 192);
    uint64 constant Position = uint64(Specs.Position >> 192);
    uint64 constant HostAsset = uint64(Specs.HostAsset >> 192);
    uint64 constant Transaction = uint64(Specs.Transaction >> 192);
    uint64 constant HostAccountAmount = uint64(Specs.HostAccountAmount >> 192);
}
