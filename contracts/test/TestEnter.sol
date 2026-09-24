// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";
import {Decoders} from "../codec/Decoders.sol";
import {Cursors, Cur} from "../utils/Cursors.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Specs} from "../codec/Specs.sol";
import {OutOfBounds} from "../utils/Errors.sol";

abstract contract EnterHarness {
    using Executions for Execution;
    function step(Execution memory exec, uint spec, uint amount, uint mode) internal pure virtual returns (uint, uint);

    function measureDiscard(bytes calldata input, uint spec, uint amount, uint mode) external view returns (uint gasUsed, uint position) {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.Bytes, Specs.Empty, 0), 0, input);
        uint remaining = 208 - (mode < 2 ? 0 : amount);
        uint initial = gasleft();
        while (exec.more()) {
            step(exec, spec, amount, mode);
            exec.advance(remaining);
        }
        gasUsed = initial - gasleft();
        position = exec.absolute();
    }

    function enterOnce(bytes calldata input, uint spec, uint amount, uint mode) external pure returns (uint, uint, uint, bool) {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.Bytes, Specs.Empty, 0), 0, input);
        uint original = exec.decoders;
        (uint body, uint end) = step(exec, spec, amount, mode);
        uint start;
        assembly ("memory-safe") { start := input.offset }
        return (body - start, end - start, exec.absolute() - start, original >> 32 == exec.decoders >> 32);
    }

    function measure(bytes calldata input, uint spec, uint amount, uint mode) external view returns (uint gasUsed, uint checksum) {
        Execution memory exec;
        exec.openInput(Executions.describe(Specs.Empty, Specs.Bytes, Specs.Empty, 0), 0, input);
        uint beforeGas = gasleft();
        while (exec.more()) {
            (uint body, uint end) = step(exec, spec, amount, mode);
            checksum += end - body;
            exec.advance(end - exec.absolute());
        }
        gasUsed = beforeGas - gasleft();
    }
}

contract TestEnterCurrent is EnterHarness {
    function descendOnce(
        bytes calldata input,
        uint parent,
        uint child,
        uint limit,
        uint metadata
    ) external pure returns (uint body, uint end, uint outer, uint position, bool preserved) {
        uint start;
        assembly ("memory-safe") { start := input.offset }
        Execution memory exec;
        uint original = start | ((start + limit) << 32) | (metadata & ~uint(type(uint64).max));
        exec.decoders = original;
        (body, end, outer) = Executions.descend(exec, parent, child);
        body -= start;
        end -= start;
        outer -= start;
        position = Executions.absolute(exec) - start;
        preserved = original >> 32 == exec.decoders >> 32;
    }

    function step(Execution memory exec, uint spec, uint amount, uint mode) internal pure override returns (uint, uint) {
        if (mode == 0) return Executions.enter(exec, spec);
        if (mode == 1) return Executions.enter(exec, bytes4(uint32(spec >> 224)));
        if (mode == 2) return Executions.enter(exec, spec, amount);
        return Executions.enter(exec, bytes4(uint32(spec >> 224)), amount);
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
        uint current = uint32(exec.decoders);
        uint next;
        (body, next, end) = Blocks.enter(current, spec, amount);
        seek(exec, next);
    }
    function legacy(Execution memory exec, bytes4 key, uint amount) internal pure returns (uint body, uint end) {
        uint current = uint32(exec.decoders);
        uint next;
        (body, next, end) = Blocks.enter(current, key, amount);
        seek(exec, next);
    }
    function seek(Execution memory exec, uint next) private pure {
        uint decoders = exec.decoders;
        uint current = uint32(decoders);
        uint end = uint32(decoders >> 32);
        if (next < current || next > end) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | next;
    }
}

abstract contract DecoderEnterHarness {
    using Decoders for Cur;
    function step(Cur memory cur, uint spec, uint amount, uint mode) internal pure virtual returns (uint, uint);

    function measureDiscard(bytes calldata input, uint spec, uint amount, uint mode) external view returns (uint gasUsed, uint position) {
        Cur memory cur;
        cur.state = Cursors.create(Cursors.base(input), Cursors.base(input) + input.length, 0xa5);
        uint remaining = 208 - (mode < 2 ? 0 : amount);
        uint initial = gasleft();
        while (cur.more()) {
            step(cur, spec, amount, mode);
            cur.advance(remaining);
        }
        gasUsed = initial - gasleft();
        position = cur.absolute();
    }

    function enterOnce(bytes calldata input, uint spec, uint amount, uint mode) external pure returns (uint, uint, uint, bool) {
        Cur memory cur;
        cur.state = Cursors.create(Cursors.base(input), Cursors.base(input) + input.length, 0xa5);
        uint original = cur.state;
        (uint body, uint end) = step(cur, spec, amount, mode);
        uint start;
        assembly ("memory-safe") { start := input.offset }
        return (body - start, end - start, cur.absolute() - start, original >> 32 == cur.state >> 32);
    }

    function measure(bytes calldata input, uint spec, uint amount, uint mode) external view returns (uint gasUsed, uint checksum) {
        Cur memory cur;
        cur.state = Cursors.create(Cursors.base(input), Cursors.base(input) + input.length, 0xa5);
        uint beforeGas = gasleft();
        while (cur.more()) {
            (uint body, uint end) = step(cur, spec, amount, mode);
            checksum += end - body;
            cur.advance(end - cur.absolute());
        }
        gasUsed = beforeGas - gasleft();
    }
}

contract TestDecoderEnterCurrent is DecoderEnterHarness {
    function step(Cur memory cur, uint spec, uint amount, uint mode) internal pure override returns (uint, uint) {
        if (mode == 0) return Decoders.enter(cur, spec);
        if (mode == 1) return Decoders.enter(cur, bytes4(uint32(spec >> 224)));
        if (mode == 2) return Decoders.enter(cur, spec, amount);
        return Decoders.enter(cur, bytes4(uint32(spec >> 224)), amount);
    }
}

/// @dev Previous Decoders.enter overloads, retained for differential and gas tests.
contract TestDecoderEnterBaseline is DecoderEnterHarness {
    using Cursors for uint;
    function step(Cur memory cur, uint spec, uint amount, uint mode) internal pure override returns (uint, uint) {
        if (mode == 0) return legacy(cur, spec);
        if (mode == 1) return legacy(cur, bytes4(uint32(spec >> 224)));
        if (mode == 2) return legacy(cur, spec, amount);
        return legacy(cur, bytes4(uint32(spec >> 224)), amount);
    }
    function legacy(Cur memory cur, uint spec) internal pure returns (uint body, uint end) {
        return legacy(cur, spec, 0);
    }
    function legacy(Cur memory cur, bytes4 key) internal pure returns (uint body, uint end) {
        return legacy(cur, key, 0);
    }
    function legacy(Cur memory cur, uint spec, uint amount) internal pure returns (uint body, uint end) {
        uint next;
        (body, next, end) = Blocks.enter(cur.state.position(), spec, amount);
        cur.state = cur.state.seek(next);
    }
    function legacy(Cur memory cur, bytes4 key, uint amount) internal pure returns (uint body, uint end) {
        uint next;
        (body, next, end) = Blocks.enter(cur.state.position(), key, amount);
        cur.state = cur.state.seek(next);
    }
}
