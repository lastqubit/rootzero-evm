// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Specs} from "../codec/Specs.sol";

contract TestExecutionOutputCursors {
    using Executions for Execution;

    function encode(uint kind, bytes calldata a, bytes calldata b, uint count, uint capacity, bool whole)
        external view returns (bytes memory output, uint aCur, uint bCur, uint baseA, uint baseB, uint usedGas)
    {
        require(a.length >= 2 && b.length >= 2);
        baseA = Cursors.base(a);
        baseB = Cursors.base(b);
        aCur = Cursors.create(baseA + 1, baseA + a.length - 1);
        bCur = Cursors.create(baseB + 1, baseB + b.length - 1);
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        exec.outputAccount(bytes32(uint(77)));
        uint initial = gasleft();
        for (uint i; i < count; ++i) {
            if (whole) {
                if (kind == 0) exec.outputBlock(aCur);
                else if (kind == 1) exec.outputList(aCur);
                else if (kind == 2) exec.outputBytes(aCur);
                else if (kind == 3) exec.outputString(aCur);
                else if (kind == 4) exec.outputStep(11, 22, aCur);
                else if (kind == 5) exec.outputCall(11, 22, aCur);
                else if (kind == 6) exec.outputDispatch(11, 22, aCur);
                else if (kind == 7) exec.outputRelay(aCur, bCur);
                else if (kind == 8) exec.outputContext(bytes32(uint(33)), aCur, bCur);
                else if (kind == 9) exec.outputRecover(11, 22, bytes32(uint(33)), aCur);
                else if (kind == 10) exec.outputLabel(bytes32(uint(33)), aCur);
                else if (kind == 11) exec.outputSchema(11, aCur);
                else revert();
                continue;
            }
            if (kind == 0) exec.outputBlockWrap(Specs.Bytes, aCur);
            else if (kind == 1) exec.outputListWrap(aCur);
            else if (kind == 2) exec.outputBytesWrap(aCur);
            else if (kind == 3) exec.outputStringWrap(aCur);
            else if (kind == 4) exec.outputStepWrap(11, 22, aCur);
            else if (kind == 5) exec.outputCallWrap(11, 22, aCur);
            else if (kind == 6) exec.outputDispatchWrap(11, 22, aCur);
            else if (kind == 7) exec.outputRelayWrap(aCur, bCur);
            else if (kind == 8) exec.outputContextWrap(bytes32(uint(33)), aCur, bCur);
            else if (kind == 9) exec.outputRecoverWrap(11, 22, bytes32(uint(33)), aCur);
            else if (kind == 10) exec.outputLabelWrap(bytes32(uint(33)), aCur);
            else if (kind == 11) exec.outputSchemaWrap(11, aCur);
            else revert();
        }
        usedGas = initial - gasleft();
        output = exec.finish();
    }

    function rewrapContext(bytes calldata source, uint capacity) external pure returns (bytes memory) {
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        (bytes32 account, uint stateCur, uint inputCur,) = Blocks.unpackContext(Cursors.wrap(source));
        exec.outputContextWrap(account, stateCur, inputCur);
        return exec.finish();
    }

    function copyContext(bytes calldata source, uint capacity) external pure returns (bytes memory) {
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        (uint contextCur,) = Blocks.take(Cursors.wrap(source), Specs.Context);
        exec.outputBlock(contextCur);
        return exec.finish();
    }

    function custom(uint spec, bytes calldata source) external pure returns (bytes memory) {
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(source.length + 8);
        exec.outputBlockWrap(spec, Cursors.wrap(source));
        return exec.finish();
    }
}
