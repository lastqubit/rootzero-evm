// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Position, Quote} from "../core/Types.sol";
import {OutOfRange, UnexpectedValue} from "./Errors.sol";

/// @notice Validation helpers for decoded positions and quotes.
library Positions {
    /// @notice Require a position to satisfy inclusive packed quantity limits.
    /// @dev High 128 bits are the minimum net asset amount; low 128 bits are the
    /// maximum total debt including fees. Both lanes are literal bounds, with no
    /// sentinel values. Position quantities remain full-width uints.
    function requireLimits(Position memory position, uint limits) internal pure {
        if (position.amount < limits >> 128 || position.debt > uint128(limits)) revert OutOfRange();
    }

    /// @notice Assert that a position satisfies a decoded quote.
    /// @dev Reverts with `UnexpectedValue` for an identifier or counterparty mismatch,
    /// or `OutOfRange` for an amount below the minimum or debt above the maximum.
    /// @param position Resulting position to validate.
    /// @param quote Exact identifiers and counterparty, minimum amount, and maximum debt.
    function requireQuoted(Position memory position, Quote memory quote) internal pure {
        if (position.asset != quote.asset || position.liability != quote.liability || position.counterparty != quote.counterparty) revert UnexpectedValue();
        requireLimits(position, quote.limits);
    }
}
