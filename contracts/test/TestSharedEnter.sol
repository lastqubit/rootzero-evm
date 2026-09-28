// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
// Compare frozen previous wrappers, production shared validation, and direct alternatives.
import {Execution} from "../execution/Execution.sol";
import {ExecutionPreviousEnter} from "./PreviousEnter.sol";

import {Sizes} from "../codec/Specs.sol";
import {OutOfBounds, InvalidBlock} from "../utils/Errors.sol";
import {EnterHarness} from "./TestEnter.sol";
import {EnterNextHarness} from "./TestEnterNext.sol";

contract TestEnterNextShared is EnterNextHarness {
    constructor(uint spec) EnterNextHarness(spec) {}
    function loop(Execution memory exec, uint spec) internal pure override returns (uint checksum) {
        while (step(exec, spec)) { checksum ^= readPair(exec); }
    }
    function step(Execution memory exec, uint spec) internal pure override returns (bool) {
        uint cur = exec.input;
        uint current = uint32(cur);
        uint limit = uint32(cur >> 32);
        if (current >= limit && uint32(exec.state) >= uint32(exec.state >> 32)) return false;
        (uint body,) = LegacyBlocks.enter(current, spec);
        if (body > limit) revert OutOfBounds();
        exec.input = (cur & ~uint(type(uint32).max)) | body;
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
        uint cur = exec.input;
        uint abs = uint32(cur);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        uint max = uint32(spec >> 160);
        if (uint32(head >> 224) != uint32(spec >> 224) || len < uint32(spec >> 192)
            || (max != 0 && len > max)) revert InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (body > uint32(cur >> 32)) revert OutOfBounds();
        exec.input = (cur & ~uint(type(uint32).max)) | body;
    }
    function enter(Execution memory exec, bytes4 key) internal pure returns (uint body, uint end) {
        uint cur = exec.input;
        uint abs = uint32(cur);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        if (uint32(head >> 224) != uint32(key)) revert InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (body > uint32(cur >> 32)) revert OutOfBounds();
        exec.input = (cur & ~uint(type(uint32).max)) | body;
    }
    function enter(Execution memory exec, uint spec, uint amount) internal pure returns (uint body, uint end) {
        uint cur = exec.input;
        uint next;
        uint abs = uint32(cur);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        uint max = uint32(spec >> 160);
        if (uint32(head >> 224) != uint32(spec >> 224) || len < uint32(spec >> 192)
            || (max != 0 && len > max)) revert InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (amount > end - body) revert InvalidBlock();
        unchecked { next = body + amount; }
        if (next > uint32(cur >> 32)) revert OutOfBounds();
        exec.input = (cur & ~uint(type(uint32).max)) | next;
    }
    function enter(Execution memory exec, bytes4 key, uint amount) internal pure returns (uint body, uint end) {
        uint cur = exec.input;
        uint next;
        uint abs = uint32(cur);
        uint head;
        assembly ("memory-safe") { head := calldataload(abs) }
        uint len = uint32(head >> 192);
        if (uint32(head >> 224) != uint32(key)) revert InvalidBlock();
        unchecked { body = abs + Sizes.Header; end = body + len; }
        if (amount > end - body) revert InvalidBlock();
        unchecked { next = body + amount; }
        if (next > uint32(cur >> 32)) revert OutOfBounds();
        exec.input = (cur & ~uint(type(uint32).max)) | next;
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
