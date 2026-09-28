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
    uint constant Account = Specs.Account >> 192;
    uint constant Asset = Specs.Asset >> 192;
    uint constant Node = Specs.Node >> 192;
    uint constant Status = Specs.Status >> 192;
    uint constant Amount = Specs.Amount >> 192;
    uint constant Balance = Specs.Balance >> 192;
    uint constant AssetLiability = Specs.AssetLiability >> 192;
    uint constant AccountAsset = Specs.AccountAsset >> 192;
    uint constant Bootstrap = Specs.Bootstrap >> 192;
    uint constant Allocation = Specs.Allocation >> 192;
    uint constant Allowance = Specs.Allowance >> 192;
    uint constant Custody = Specs.Custody >> 192;
    uint constant AccountAmount = Specs.AccountAmount >> 192;
    uint constant HostAmount = Specs.HostAmount >> 192;
    uint constant HostAccountAsset = Specs.HostAccountAsset >> 192;
    uint constant Limits = Specs.Limits >> 192;
    uint constant BalanceConstraints = Specs.BalanceConstraints >> 192;
    uint constant PositionConstraints = Specs.PositionConstraints >> 192;
    uint constant Quote = Specs.Quote >> 192;
    uint constant Position = Specs.Position >> 192;
    uint constant HostAsset = Specs.HostAsset >> 192;
    uint constant Transaction = Specs.Transaction >> 192;
    uint constant HostAccountAmount = Specs.HostAccountAmount >> 192;
}
