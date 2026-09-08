// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
// Compare frozen previous wrappers, production shared validation, and direct alternatives.
import {Execution} from "../execution/Execution.sol";
import {ExecutionPreviousEnter, DecoderPreviousEnter} from "./PreviousEnter.sol";
import {Cur} from "../utils/Cursors.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Sizes} from "../codec/Specs.sol";
import {OutOfBounds} from "../utils/Errors.sol";
import {EnterHarness, DecoderEnterHarness} from "./TestEnter.sol";
import {EnterNextHarness} from "./TestEnterNext.sol";

contract TestEnterNextShared is EnterNextHarness {
    constructor(uint spec) EnterNextHarness(spec) {}
    function loop(Execution memory exec, uint spec) internal pure override returns (uint checksum) {
        while (step(exec, spec)) { checksum ^= readPair(exec); }
    }
    function step(Execution memory exec, uint spec) internal pure override returns (bool) {
        uint decoders = exec.decoders;
        uint current = uint32(decoders);
        uint limit = uint32(decoders >> 32);
        if (current >= limit && uint32(decoders >> 64) >= uint32(decoders >> 96)) return false;
        (uint body,) = Blocks.enter(current, spec);
        if (body > limit) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | body;
        return true;
    }
}




contract TestExecutionPreviousEnter is EnterHarness {
    function step(Execution memory exec, uint spec, uint amount, uint mode) internal pure override returns (uint, uint) {
        if (mode == 0) return ExecutionPreviousEnter.enter(exec, spec);
        if (mode == 1) return ExecutionPreviousEnter.enter(exec, bytes4(uint32(spec >> 224)));
        if (mode == 2) return ExecutionPreviousEnter.enter(exec, spec, amount);
        return ExecutionPreviousEnter.enter(exec, bytes4(uint32(spec >> 224)), amount);
    }
}

library ExecutionDirectEnter {
    function enter(Execution memory exec, uint spec) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        uint abs = uint32(decoders);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        uint max = uint32(spec >> 160);
        if (uint32(head >> 224) != uint32(spec >> 224) || len < uint32(spec >> 192)
            || (max != 0 && len > max)) revert Blocks.InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (body > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | body;
    }
    function enter(Execution memory exec, bytes4 key) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        uint abs = uint32(decoders);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        if (uint32(head >> 224) != uint32(key)) revert Blocks.InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (body > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | body;
    }
    function enter(Execution memory exec, uint spec, uint amount) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        uint next;
        uint abs = uint32(decoders);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        uint max = uint32(spec >> 160);
        if (uint32(head >> 224) != uint32(spec >> 224) || len < uint32(spec >> 192)
            || (max != 0 && len > max)) revert Blocks.InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (amount > end - body) revert Blocks.InvalidBlock();
        unchecked { next = body + amount; }
        if (next > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | next;
    }
    function enter(Execution memory exec, bytes4 key, uint amount) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        uint next;
        uint abs = uint32(decoders);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        if (uint32(head >> 224) != uint32(key)) revert Blocks.InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (amount > end - body) revert Blocks.InvalidBlock();
        unchecked { next = body + amount; }
        if (next > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | next;
    }
}
contract TestExecutionDirectEnter is EnterHarness {
    function step(Execution memory exec, uint spec, uint amount, uint mode) internal pure override returns (uint, uint) {
        if (mode == 0) return ExecutionDirectEnter.enter(exec, spec);
        if (mode == 1) return ExecutionDirectEnter.enter(exec, bytes4(uint32(spec >> 224)));
        if (mode == 2) return ExecutionDirectEnter.enter(exec, spec, amount);
        return ExecutionDirectEnter.enter(exec, bytes4(uint32(spec >> 224)), amount);
    }
}


contract TestDecoderPreviousEnter is DecoderEnterHarness {
    function step(Cur memory cur, uint spec, uint amount, uint mode) internal pure override returns (uint, uint) {
        if (mode == 0) return DecoderPreviousEnter.enter(cur, spec);
        if (mode == 1) return DecoderPreviousEnter.enter(cur, bytes4(uint32(spec >> 224)));
        if (mode == 2) return DecoderPreviousEnter.enter(cur, spec, amount);
        return DecoderPreviousEnter.enter(cur, bytes4(uint32(spec >> 224)), amount);
    }
}

library DecoderDirectEnter {
    function enter(Cur memory cur, uint spec) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        uint abs = uint32(state);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        uint max = uint32(spec >> 160);
        if (uint32(head >> 224) != uint32(spec >> 224) || len < uint32(spec >> 192)
            || (max != 0 && len > max)) revert Blocks.InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (body > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | body;
    }
    function enter(Cur memory cur, bytes4 key) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        uint abs = uint32(state);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        if (uint32(head >> 224) != uint32(key)) revert Blocks.InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (body > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | body;
    }
    function enter(Cur memory cur, uint spec, uint amount) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        uint next;
        uint abs = uint32(state);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        uint max = uint32(spec >> 160);
        if (uint32(head >> 224) != uint32(spec >> 224) || len < uint32(spec >> 192)
            || (max != 0 && len > max)) revert Blocks.InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (amount > end - body) revert Blocks.InvalidBlock();
        unchecked { next = body + amount; }
        if (next > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | next;
    }
    function enter(Cur memory cur, bytes4 key, uint amount) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        uint next;
        uint abs = uint32(state);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        if (uint32(head >> 224) != uint32(key)) revert Blocks.InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (amount > end - body) revert Blocks.InvalidBlock();
        unchecked { next = body + amount; }
        if (next > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | next;
    }
}
contract TestDecoderDirectEnter is DecoderEnterHarness {
    function step(Cur memory cur, uint spec, uint amount, uint mode) internal pure override returns (uint, uint) {
        if (mode == 0) return DecoderDirectEnter.enter(cur, spec);
        if (mode == 1) return DecoderDirectEnter.enter(cur, bytes4(uint32(spec >> 224)));
        if (mode == 2) return DecoderDirectEnter.enter(cur, spec, amount);
        return DecoderDirectEnter.enter(cur, bytes4(uint32(spec >> 224)), amount);
    }
}
