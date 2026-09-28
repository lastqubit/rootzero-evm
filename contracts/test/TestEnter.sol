// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {Execution, Executions} from "../execution/Execution.sol";

import {Specs} from "../codec/Specs.sol";
import {OutOfBounds} from "../utils/Errors.sol";

abstract contract EnterHarness {
    using Executions for Execution;
    function step(Execution memory exec, uint spec, uint amount, uint mode) internal pure virtual returns (uint, uint);

    function finishDiscard(Execution memory exec, uint remaining) internal pure virtual { exec.advance(remaining); }

    function measureDiscard(bytes calldata input, uint spec, uint amount, uint mode) external view returns (uint gasUsed, uint position) {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.Bytes, Specs.Empty, 0), 0, input);
        uint remaining = 208 - (mode < 2 ? 0 : amount);
        uint initial = gasleft();
        while (exec.more()) {
            step(exec, spec, amount, mode);
            finishDiscard(exec, remaining);
        }
        gasUsed = initial - gasleft();
        position = uint32(exec.input);
    }

    function enterOnce(bytes calldata input, uint spec, uint amount, uint mode) external pure returns (uint, uint, uint, bool) {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.Bytes, Specs.Empty, 0), 0, input);
        uint original = exec.input;
        (uint body, uint end) = step(exec, spec, amount, mode);
        uint start;
        assembly ("memory-safe") { start := input.offset }
        return (body - start, end - start, uint32(exec.input) - start, original >> 32 == exec.input >> 32);
    }

    function measure(bytes calldata input, uint spec, uint amount, uint mode) external view returns (uint gasUsed, uint checksum) {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.Bytes, Specs.Empty, 0), 0, input);
        uint beforeGas = gasleft();
        while (exec.more()) {
            (uint body, uint end) = step(exec, spec, amount, mode);
            checksum += end - body;
            exec.advance(end - uint32(exec.input));
        }
        gasUsed = beforeGas - gasleft();
    }
}

contract TestEnterCurrent is EnterHarness {
    function finishDiscard(Execution memory, uint) internal pure override {}

    function step(Execution memory exec, uint spec, uint amount, uint mode) internal pure override returns (uint abs, uint end) {
        uint payloadCur;
        uint prefix = mode < 2 ? 0 : amount;
        if (mode == 0 || mode == 2) (abs, payloadCur) = Executions.enter(exec, spec, prefix);
        else (abs, payloadCur) = Executions.enter(exec, bytes4(uint32(spec >> 224)), prefix);
        end = uint32(payloadCur >> 32);
    }

}

/// @dev Baseline implementation retained to compare gas and validation behavior.
contract TestEnterBaseline is EnterHarness {
    function step(Execution memory exec, uint spec, uint amount, uint mode) internal pure override returns (uint, uint) {
        if (mode == 0) return legacy(exec, spec);
        if (mode == 1) return legacy(exec, bytes4(uint32(spec >> 224)));
        if (mode == 2) return legacy(exec, spec, amount);
        return legacy(exec, bytes4(uint32(spec >> 224)), amount);
    }
    function legacy(Execution memory exec, uint spec) internal pure returns (uint body, uint end) {
        return legacy(exec, spec, 0);
    }
    function legacy(Execution memory exec, bytes4 key) internal pure returns (uint body, uint end) {
        return legacy(exec, key, 0);
    }
    function legacy(Execution memory exec, uint spec, uint amount) internal pure returns (uint body, uint end) {
        uint current = uint32(exec.input);
        uint next;
        (body, next, end) = LegacyBlocks.enter(current, spec, amount);
        seek(exec, next);
    }
    function legacy(Execution memory exec, bytes4 key, uint amount) internal pure returns (uint body, uint end) {
        uint current = uint32(exec.input);
        uint next;
        (body, next, end) = LegacyBlocks.enter(current, key, amount);
        seek(exec, next);
    }
    function seek(Execution memory exec, uint next) private pure {
        uint cur = exec.input;
        uint current = uint32(cur);
        uint end = uint32(cur >> 32);
        if (next < current || next > end) revert OutOfBounds();
        exec.input = (cur & ~uint(type(uint32).max)) | next;
    }
}
