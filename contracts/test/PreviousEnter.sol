// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
// Frozen pre-shared-validation implementation for differential benchmarks.

import {Specs, Sizes} from "../codec/Specs.sol";
import {Execution} from "../execution/Execution.sol";
import {OutOfBounds, InvalidBlock} from "../utils/Errors.sol";
library PreviousEnterBlocks {
    function enter(uint abs, uint spec) internal pure returns (uint body, uint end) {
        uint head;
        assembly ("memory-safe") {
            head := calldataload(abs)
        }
        uint len = uint32(head >> 192);
        if (!Specs.matches(spec, bytes4(uint32(head >> 224)), len)) revert InvalidBlock();

        unchecked {
            body = abs + Sizes.Header;
            end = body + len;
        }
    }
    function enter(
        uint abs,
        uint spec,
        uint amount
    ) internal pure returns (uint body, uint next, uint end) {
        (body, end) = enter(abs, spec);
        if (amount > end - body) revert InvalidBlock();
        unchecked {
            next = body + amount;
        }
    }
    function enter(uint abs, bytes4 key) internal pure returns (uint body, uint end) {
        uint head;
        assembly ("memory-safe") {
            head := calldataload(abs)
        }
        if (uint32(head >> 224) != uint32(key)) revert InvalidBlock();
        uint len = uint32(head >> 192);
        unchecked {
            body = abs + Sizes.Header;
            end = body + len;
        }
    }
    function enter(
        uint abs,
        bytes4 key,
        uint amount
    ) internal pure returns (uint body, uint next, uint end) {
        (body, end) = enter(abs, key);
        if (amount > end - body) revert InvalidBlock();
        unchecked {
            next = body + amount;
        }
    }
}

library ExecutionPreviousEnter {
    function enter(Execution memory exec, uint spec) internal pure returns (uint body, uint end) {
        uint cur = exec.input;
        (body, end) = PreviousEnterBlocks.enter(uint32(cur), spec);
        if (body > uint32(cur >> 32)) revert OutOfBounds();
        exec.input = (cur & ~uint(type(uint32).max)) | body;
    }
    function enter(Execution memory exec, bytes4 key) internal pure returns (uint body, uint end) {
        uint cur = exec.input;
        (body, end) = PreviousEnterBlocks.enter(uint32(cur), key);
        if (body > uint32(cur >> 32)) revert OutOfBounds();
        exec.input = (cur & ~uint(type(uint32).max)) | body;
    }
    function enter(Execution memory exec, uint spec, uint amount) internal pure returns (uint body, uint end) {
        uint cur = exec.input;
        uint next;
        (body, next, end) = PreviousEnterBlocks.enter(uint32(cur), spec, amount);
        if (next > uint32(cur >> 32)) revert OutOfBounds();
        exec.input = (cur & ~uint(type(uint32).max)) | next;
    }
    function enter(Execution memory exec, bytes4 key, uint amount) internal pure returns (uint body, uint end) {
        uint cur = exec.input;
        uint next;
        (body, next, end) = PreviousEnterBlocks.enter(uint32(cur), key, amount);
        if (next > uint32(cur >> 32)) revert OutOfBounds();
        exec.input = (cur & ~uint(type(uint32).max)) | next;
    }
}
