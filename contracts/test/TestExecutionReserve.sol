// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";
import {Encoder} from "../codec/Encoder.sol";

contract TestExecutionReserve {
    using Executions for Execution;

    function write(uint capacity, uint keep, uint count) external payable returns (bytes memory output, uint metadata) {
        require(keep > 0 && keep <= 32);
        Execution memory exec = Executions.open();
        (exec.buffer, exec.output) = Encoder.init(capacity);
        exec.output |= uint(0xabcdef) << 64;
        for (uint i; i < count; i++) {
            uint abs = exec.reserve(keep);
            // Full-word stores exercise the retained scratch space when keep < 32.
            Encoder.write32(abs, bytes32(type(uint).max));
        }
        exec.reserve(0);
        metadata = exec.output >> 64;
        output = exec.finish();
    }
}
