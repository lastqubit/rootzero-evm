// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ValueOverflow, ZeroAmount} from "./Errors.sol";

/// @notice General-purpose checked arithmetic helpers.
library Math {
    /// @notice Scale a value by a ratio, rounding down.
    /// @dev Reverts ZeroAmount for a zero denominator and ValueOverflow if the
    /// intermediate product exceeds uint256, even when the quotient would fit.
    /// Does not impose any narrower limit on the result.
    /// @param value Value to scale.
    /// @param numerator Ratio multiplier; zero produces zero.
    /// @param denominator Nonzero ratio divisor.
    /// @return Scaled value with floor division.
    function scale(uint value, uint numerator, uint denominator) internal pure returns (uint) {
        if (denominator == 0) revert ZeroAmount();
        if (numerator == 1 && denominator == 1) return value;
        if (value != 0 && numerator > type(uint).max / value) revert ValueOverflow();
        unchecked {
            return (value * numerator) / denominator;
        }
    }
}
