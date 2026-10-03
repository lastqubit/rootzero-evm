// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Encoder, Execution, Executions} from "../Codec.sol";
import {Specs} from "../codec/Specs.sol";
import {Cursors} from "../utils/Cursors.sol";

contract TestExecutionFinalization {
    using Executions for Execution;

    // flags: 1 = close, 2 = log output, 4 = initialize writer.
    function finalize(uint flags, uint budget, uint capacity, uint count,
        bytes calldata input, bytes calldata state)
        external returns (bytes memory output, uint credit, uint remaining)
    {
        Execution memory exec;
        exec.budget = budget;
        exec.input = Cursors.wrap(input);
        exec.state = Cursors.wrap(state);
        if ((flags & 4) != 0) (exec.buffer, exec.output) = Encoder.init(capacity);
        for (uint i; i < count; ++i) exec.outputBalance(bytes32(i + 1), type(uint).max - i);
        uint descriptor = Executions.describe(0, 0, Specs.Balance | (flags & 2));
        if ((flags & 1) != 0) (output, credit) = exec.close(123, descriptor);
        else output = exec.finish(123, descriptor);
        remaining = exec.budget;
    }
    function checkEnd(uint input, uint state) external pure {
        Execution memory exec;
        exec.input = input;
        exec.state = state;
        exec.expectEnd();
    }
}
