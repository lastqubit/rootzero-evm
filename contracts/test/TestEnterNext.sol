// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions} from "../execution/Execution.sol";
import {ExecutionPreviousEnter} from "./PreviousEnter.sol";
import {Sizes} from "../codec/Specs.sol";
import {Blocks} from "../codec/Blocks.sol";
import {OutOfBounds} from "../utils/Errors.sol";

/// @dev Frozen inline implementation retained for gas and behavior comparisons.
library PreviousInlineEnterNext {
    function enterNext(Execution memory exec, uint spec) internal pure returns (bool) {
        uint decoders = exec.decoders;
        uint current = uint32(decoders);
        uint limit = uint32(decoders >> 32);
        if (current >= limit && uint32(decoders >> 64) >= uint32(decoders >> 96)) return false;

        uint head;
        assembly ("memory-safe") { head := calldataload(current) }
        uint length = uint32(head >> 192);
        uint max = uint32(spec >> 160);
        if (uint32(head >> 224) != uint32(spec >> 224) || length < uint32(spec >> 192)
            || (max != 0 && length > max)) revert Blocks.InvalidBlock();

        uint body;
        // current is uint32; the upper bound below also keeps body in that lane.
        unchecked { body = current + Sizes.Header; }
        if (body > limit) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | body;
        return true;
    }
}

abstract contract EnterNextHarness {
    using Executions for Execution;
    uint private immutable parentSpec;
    constructor(uint spec) { parentSpec = spec; }
    function step(Execution memory exec, uint spec) internal pure virtual returns (bool);
    function loop(Execution memory exec, uint spec) internal pure virtual returns (uint);

    function readPair(Execution memory exec) internal pure returns (uint checksum) {
        (bytes32 account, bytes32 asset, uint amount) = exec.unpackAccountAmount();
        checksum = uint(account) ^ uint(asset) ^ amount;
        (account, asset, amount) = exec.unpackAccountAmount();
        checksum ^= uint(account) ^ uint(asset) ^ amount;
    }

    function measure(bytes calldata input) external view returns (uint usedGas, uint checksum, uint cursor) {
        Execution memory exec;
        assembly ("memory-safe") {
            mstore(add(exec, 64), or(input.offset, shl(32, add(input.offset, input.length))))
        }
        uint initial = gasleft();
        checksum = loop(exec, parentSpec);
        usedGas = initial - gasleft();
        cursor = exec.decoders;
    }

    function enterOnce(bytes calldata input, uint spec, uint position, uint limit, uint state, uint flags)
        external pure returns (bool entered, uint cursor)
    {
        uint base;
        assembly ("memory-safe") { base := input.offset }
        Execution memory exec;
        exec.decoders = (base + position) | ((base + limit) << 32) | (state << 64) | (flags << 128);
        entered = step(exec, spec);
        cursor = exec.decoders;
    }
}

contract TestEnterNextBaseline is EnterNextHarness {
    constructor(uint spec) EnterNextHarness(spec) {}
    function loop(Execution memory exec, uint spec) internal pure override returns (uint checksum) {
        while (Executions.more(exec)) {
            ExecutionPreviousEnter.enter(exec, spec);
            checksum ^= readPair(exec);
        }
    }
    function step(Execution memory exec, uint spec) internal pure override returns (bool) {
        if (!Executions.more(exec)) return false;
        ExecutionPreviousEnter.enter(exec, spec);
        return true;
    }
}

contract TestEnterNextCurrent is EnterNextHarness {
    constructor(uint spec) EnterNextHarness(spec) {}
    function loop(Execution memory exec, uint spec) internal pure override returns (uint checksum) {
        while (Executions.more(exec)) {
            Executions.enter(exec, spec);
            checksum ^= readPair(exec);
        }
    }
    function step(Execution memory exec, uint spec) internal pure override returns (bool) {
        if (!Executions.more(exec)) return false;
        Executions.enter(exec, spec);
        return true;
    }
}

contract TestEnterNextInline is EnterNextHarness {
    constructor(uint spec) EnterNextHarness(spec) {}
    function loop(Execution memory exec, uint spec) internal pure override returns (uint checksum) {
        while (PreviousInlineEnterNext.enterNext(exec, spec)) {
            checksum ^= readPair(exec);
        }
    }
    function step(Execution memory exec, uint spec) internal pure override returns (bool) {
        return PreviousInlineEnterNext.enterNext(exec, spec);
    }
}
