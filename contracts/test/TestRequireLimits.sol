// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";
import {Specs} from "../codec/Specs.sol";
import {Position} from "../core/Types.sol";
import {Positions} from "../utils/Positions.sol";

contract TestRequireLimits {
    using Executions for Execution;

    function measureDirect(bytes calldata input, uint amount, uint debt)
        external view returns (uint used, uint cursor)
    {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.Limits, Specs.Empty, 0), 0, input);
        Position memory position;
        position.amount = amount;
        position.debt = debt;
        uint start = gasleft();
        while (exec.more()) exec.requireLimits(position.amount, position.debt);
        used = start - gasleft();
        cursor = exec.absolute();
    }

    function measureDecoded(bytes calldata input, uint amount, uint debt)
        external view returns (uint used, uint cursor)
    {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.Limits, Specs.Empty, 0), 0, input);
        Position memory position;
        position.amount = amount;
        position.debt = debt;
        uint start = gasleft();
        while (exec.more()) Positions.requireLimits(position, exec.unpackLimits());
        used = start - gasleft();
        cursor = exec.absolute();
    }
}
