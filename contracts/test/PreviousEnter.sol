// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
// Frozen pre-shared-validation implementation for differential benchmarks.
import {Blocks} from "../codec/Blocks.sol";
import {Specs, Sizes} from "../codec/Specs.sol";
import {Execution} from "../execution/Execution.sol";
import {Cur} from "../utils/Cursors.sol";
import {OutOfBounds} from "../utils/Errors.sol";
library PreviousEnterBlocks {
    function enter(uint abs, uint spec) internal pure returns (uint body, uint end) {
        uint head;
        assembly ("memory-safe") {
            head := calldataload(abs)
        }
        uint len = uint32(head >> 192);
        if (!Specs.matches(spec, bytes4(uint32(head >> 224)), len)) revert Blocks.InvalidBlock();

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
        if (amount > end - body) revert Blocks.InvalidBlock();
        unchecked {
            next = body + amount;
        }
    }
    function enter(uint abs, bytes4 key) internal pure returns (uint body, uint end) {
        uint head;
        assembly ("memory-safe") {
            head := calldataload(abs)
        }
        if (uint32(head >> 224) != uint32(key)) revert Blocks.InvalidBlock();
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
        if (amount > end - body) revert Blocks.InvalidBlock();
        unchecked {
            next = body + amount;
        }
    }
}

library ExecutionPreviousEnter {
    function enter(Execution memory exec, uint spec) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        (body, end) = PreviousEnterBlocks.enter(uint32(decoders), spec);
        if (body > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | body;
    }
    function enter(Execution memory exec, bytes4 key) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        (body, end) = PreviousEnterBlocks.enter(uint32(decoders), key);
        if (body > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | body;
    }
    function enter(Execution memory exec, uint spec, uint amount) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        uint next;
        (body, next, end) = PreviousEnterBlocks.enter(uint32(decoders), spec, amount);
        if (next > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | next;
    }
    function enter(Execution memory exec, bytes4 key, uint amount) internal pure returns (uint body, uint end) {
        uint decoders = exec.decoders;
        uint next;
        (body, next, end) = PreviousEnterBlocks.enter(uint32(decoders), key, amount);
        if (next > uint32(decoders >> 32)) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | next;
    }
}

library DecoderPreviousEnter {
    function enter(Cur memory cur, uint spec) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        (body, end) = PreviousEnterBlocks.enter(uint32(state), spec);
        if (body > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | body;
    }
    function enter(Cur memory cur, bytes4 key) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        (body, end) = PreviousEnterBlocks.enter(uint32(state), key);
        if (body > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | body;
    }
    function enter(Cur memory cur, uint spec, uint amount) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        uint next;
        (body, next, end) = PreviousEnterBlocks.enter(uint32(state), spec, amount);
        if (next > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | next;
    }
    function enter(Cur memory cur, bytes4 key, uint amount) internal pure returns (uint body, uint end) {
        uint state = cur.state;
        uint next;
        (body, next, end) = PreviousEnterBlocks.enter(uint32(state), key, amount);
        if (next > uint32(state >> 32)) revert OutOfBounds();
        cur.state = (state & ~uint(type(uint32).max)) | next;
    }
}
