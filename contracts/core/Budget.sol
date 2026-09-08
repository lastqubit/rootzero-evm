// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {InsufficientValue} from "../utils/Errors.sol";

/// @notice Mutable native-value budget shared across internal calls.
struct Budget {
    /// @dev Remaining unspent native value in wei.
    uint remaining;
}

/// @title Budgets
/// @notice Opening and mutation helpers for standalone native-value budgets.
library Budgets {
    /// @notice Open a standalone budget containing the current call value.
    /// @return budget Budget initialized with `msg.value`.
    function open() internal view returns (Budget memory budget) {
        budget.remaining = msg.value;
    }

    /// @notice Deduct an exact native value from `budget`.
    /// @param budget Mutable budget to debit.
    /// @param value Native value to consume in wei.
    /// @return The consumed native value.
    function useValue(Budget memory budget, uint value) internal pure returns (uint) {
        if (value > budget.remaining) revert InsufficientValue();
        unchecked { budget.remaining -= value; }
        return value;
    }

    /// @notice Add trusted native value to `budget`.
    /// @dev This updates accounting only. The caller must ensure the added value
    /// is backed by native value held by the host or otherwise made available.
    /// @param budget Mutable budget to credit.
    /// @param value Native value to add in wei.
    function addValue(Budget memory budget, uint value) internal pure {
        budget.remaining += value;
    }

    /// @notice Deduct an exact native value from a scalar budget.
    /// @param budget Remaining native value in wei.
    /// @param value Native value to consume in wei.
    /// @return remaining Native value remaining after the deduction.
    function useValue(uint budget, uint value) internal pure returns (uint remaining) {
        if (value > budget) revert InsufficientValue();
        unchecked { remaining = budget - value; }
    }

    /// @notice Deduct the EVM value lane of `resources` from `budget`.
    /// @dev `resources` is not a native value. This helper explicitly extracts
    /// its low 128-bit EVM value lane and widens that lane to a plain `uint`.
    /// @param budget Mutable budget to debit.
    /// @param resources Packed resources whose low 128 bits contain native value.
    /// @return value Native value to forward in wei.
    function useResourceValue(Budget memory budget, uint resources) internal pure returns (uint value) {
        value = uint128(resources);
        useValue(budget, value);
    }

    /// @notice Deduct the EVM value lane of `resources` from a scalar budget.
    /// @dev `resources` is not a native value. This helper explicitly extracts
    /// its low 128-bit EVM value lane and widens that lane to a plain `uint`.
    /// @param budget Remaining native value in wei.
    /// @param resources Packed resources whose low 128 bits contain native value.
    /// @return remaining Native value remaining after the deduction.
    /// @return value Native value consumed from the budget.
    function useResourceValue(
        uint budget,
        uint resources
    ) internal pure returns (uint remaining, uint value) {
        value = uint128(resources);
        remaining = useValue(budget, value);
    }

    /// @notice Remove and return all remaining value from `budget`.
    /// @param budget Mutable budget to drain.
    /// @return value Native value removed from the budget.
    function drain(Budget memory budget) internal pure returns (uint value) {
        value = budget.remaining;
        budget.remaining = 0;
    }
}
