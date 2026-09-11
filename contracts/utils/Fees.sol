// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {MAX_BPS} from "./Utils.sol";

/// @notice Basis-point fees that fit inclusive amount limits.
/// @dev Fees round up to whole asset units and are never partially charged. Zero means either no
/// fee was calculated or the full fee cannot fit; it does not validate the amount.
library Fees {
    /// @dev Split the product to avoid intermediate overflow, even at uint maximum.
    function within(uint amount, uint16 bps, uint room) private pure returns (uint) {
        if (bps == 0) return 0;
        uint whole = amount / MAX_BPS;
        if (whole > room / bps) return 0;
        uint fee = whole * bps;
        uint remainder = ((amount % MAX_BPS) * bps + MAX_BPS - 1) / MAX_BPS;
        if (remainder > room - fee) return 0;
        return fee + remainder;
    }

    /// @notice Return the fee deductible while leaving at least `limit`.
    /// @param amount Original amount on which the fee is calculated.
    /// @param bps Fee rate with 10_000 basis points equal to 100%.
    /// @param limit Inclusive minimum amount remaining after deduction.
    /// @return Fee quantity, or zero if the amount or full fee cannot fit the limit.
    function deductible(uint amount, uint16 bps, uint limit) internal pure returns (uint) {
        if (amount < limit) return 0;
        return within(amount, bps, amount - limit);
    }

    /// @notice Return the fee addable without exceeding `limit`.
    /// @param amount Original amount on which the surcharge is calculated.
    /// @param bps Fee rate with 10_000 basis points equal to 100%.
    /// @param limit Inclusive maximum amount including the fee.
    /// @return Fee quantity, or zero if the amount or full fee cannot fit the limit.
    function addable(uint amount, uint16 bps, uint limit) internal pure returns (uint) {
        if (amount > limit) return 0;
        return within(amount, bps, limit - amount);
    }

    /// @notice Return the fee magnitude for a signed basis-point rate.
    /// @param amount Original amount on which the fee is calculated.
    /// @param bps Positive to add, negative to deduct, or zero for no fee.
    /// @param limit Inclusive maximum total for positive bps, or minimum remaining amount for negative bps.
    /// @return Unsigned fee quantity, or zero if no fee is calculated or the full fee cannot fit.
    function calculate(uint amount, int16 bps, uint limit) internal pure returns (uint) {
        if (bps < 0) return deductible(amount, uint16(uint32(-int32(bps))), limit);
        return addable(amount, uint16(bps), limit);
    }
}
