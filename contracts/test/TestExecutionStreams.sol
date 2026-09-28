// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";
import {Specs} from "../codec/Specs.sol";
import {Execution, Executions} from "../execution/Execution.sol";

contract TestExecutionStreams {
    function validate(bytes calldata data, uint start, uint end, bytes4 key, uint header, bool fixedSize) external pure {
        uint base;
        assembly ("memory-safe") { base := data.offset }
        uint cur = (base + start) | ((base + end) << 32);
        if (fixedSize) Blocks.expectRunFixed(cur, header);
        else Blocks.expectRun(cur, key);
    }

    function select(bytes calldata data, bytes4 key, uint header, bool fixedSize, bool state, bool declared)
        external pure returns (bytes calldata selected, uint selectedCur, uint beforeCur, uint afterCur, uint otherCur)
    {
        Execution memory exec;
        uint descriptor = Executions.describe(Specs.Empty, declared ? Specs.Bytes : Specs.Empty, Specs.Empty, 0);
        Executions.openInput(exec, descriptor, 0, data);
        if (state) {
            exec.state = exec.input;
            exec.input = 0;
        }
        beforeCur = state ? exec.state : exec.input;
        if (state) selectedCur = fixedSize ? Executions.takeStateFixed(exec, header) : Executions.takeState(exec, key);
        else selectedCur = fixedSize ? Executions.takeInputFixed(exec, header) : Executions.takeInput(exec, key);
        selected = Blocks.toBytesChecked(selectedCur);
        afterCur = state ? exec.state : exec.input;
        otherCur = state ? exec.input : exec.state;
    }
}
