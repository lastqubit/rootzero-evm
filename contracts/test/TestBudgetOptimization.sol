// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Budget, Budgets} from "../core/Budget.sol";
import {InsufficientValue} from "../utils/Errors.sol";
library PreviousBudgets {
    function useValue(Budget memory budget, uint value) internal pure returns (uint) {
        if (value > budget.remaining) revert InsufficientValue();
        budget.remaining -= value;
        return value;
    }

    function useValue(uint budget, uint value) internal pure returns (uint remaining) {
        if (value > budget) revert InsufficientValue();
        remaining = budget - value;
    }

    function useResourceValue(Budget memory budget, uint resources) internal pure returns (uint value) {
        value = uint128(resources);
        useValue(budget, value);
    }

    function useResourceValue(
        uint budget,
        uint resources
    ) internal pure returns (uint remaining, uint value) {
        value = uint128(resources);
        remaining = useValue(budget, value);
    }
}
contract TestBudgetOptimization {
    function measure(bool optimized, uint mode, uint amount, uint value)
        external view returns(uint usedGas, uint remaining, uint consumed) {
        Budget memory budget = Budget(amount);
        uint initial = gasleft();
        if (mode == 0) {
            consumed = optimized ? Budgets.useValue(budget, value) : PreviousBudgets.useValue(budget, value);
            remaining = budget.remaining;
        } else if (mode == 1) {
            remaining = optimized ? Budgets.useValue(amount, value) : PreviousBudgets.useValue(amount, value);
            consumed = value;
        } else if (mode == 2) {
            consumed = optimized ? Budgets.useResourceValue(budget, value) : PreviousBudgets.useResourceValue(budget, value);
            remaining = budget.remaining;
        } else {
            if (optimized) (remaining, consumed) = Budgets.useResourceValue(amount, value);
            else (remaining, consumed) = PreviousBudgets.useResourceValue(amount, value);
        }
        usedGas = initial - gasleft();
    }
}
