// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Execution, Executions} from "../execution/Execution.sol";
import {Logs} from "../codec/Logs.sol";

abstract contract ContextLogHarness {
    function emitContext(Execution memory exec, uint descriptor) internal virtual;
    function measure(bytes calldata context, uint mask) external returns (uint gasUsed, bytes32 account, uint budget, uint state, uint input) {
        Execution memory exec;
        uint descriptor = Executions.describe(mask & 1, (mask >> 1) & 1, 0);
        Executions.openContext(exec, descriptor, 19, context);
        uint beforeGas = gasleft();
        emitContext(exec, descriptor);
        gasUsed = beforeGas - gasleft();
        return (gasUsed, exec.account, exec.budget, exec.state, exec.input);
    }
}
contract ContextLogsCombined is ContextLogHarness {
    function emitContext(Execution memory exec, uint descriptor) internal override {
        Executions.logContext(exec, 123, descriptor);
    }
}
contract ContextLogsSeparate is ContextLogHarness {
    function emitContext(Execution memory exec, uint descriptor) internal override {
        // Previous runner: separate streams without their container headers.
        if (descriptor & Executions.LogState != 0) Logs.copy(123, exec.state);
        if (descriptor & Executions.LogInput != 0) Logs.copy(123, exec.input);
    }
}

// Frozen header-preserving helper before optimizing range selection.
contract ContextLogsPrevious is ContextLogHarness {
    function emitContext(Execution memory exec, uint descriptor) internal override {
        uint selected = descriptor & (Executions.LogState | Executions.LogInput);
        if (selected == 0) return;
        uint abs = uint32(selected & Executions.LogState != 0 ? exec.state : exec.input) - 8;
        uint end = uint32((selected & Executions.LogInput != 0 ? exec.input : exec.state) >> 32);
        Logs.copy(123, abs, end - abs);
    }
}
