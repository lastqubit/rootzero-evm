// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";
import {Cursors} from "../utils/Cursors.sol";

contract TestExecutionSelection {
    using Executions for Execution;

    function inspect(bytes calldata data, uint length, uint spec, uint amount, uint mode)
        external pure returns (uint abs, uint selected, uint input, uint state, uint base)
    {
        require(length <= data.length);
        base = Cursors.base(data);
        Execution memory exec;
        exec.input = base | ((base + length) << 32) | (uint(0xa5) << 64);
        exec.state = 0x12345678;
        bytes4 key = bytes4(uint32(spec >> 224));
        uint header = spec >> 192;
        if (mode == 0) (abs, selected) = exec.enter(spec, amount);
        else if (mode == 1) (abs, selected) = exec.enter(key, amount);
        else if (mode == 2) (abs, selected) = exec.enterFixed(header, amount);
        else if (mode == 3) (abs, selected) = exec.enterExact(spec, amount);
        else if (mode == 4) selected = exec.take();
        else if (mode == 5) selected = exec.take(spec);
        else if (mode == 6) selected = exec.take(key);
        else if (mode == 7) selected = exec.takeFixed(header);
        else if (mode == 8) selected = exec.takeExact(spec);
        else if (mode == 9) selected = exec.unpack(spec);
        else if (mode == 10) selected = exec.unpack(key);
        else if (mode == 11) selected = exec.unpackFixed(header);
        else if (mode == 12) selected = exec.unpackExact(spec);
        else if (mode == 13) selected = exec.takeFixedExact(header);
        else selected = exec.unpackFixedExact(header);
        input = exec.input;
        state = exec.state;
    }
}
