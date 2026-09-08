// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {Keys} from "../codec/Keys.sol";
import {Sizes} from "../codec/Specs.sol";
import {max32} from "../utils/Utils.sol";

/// @dev Frozen pre-optimization scans for differential testing.
library PreviousBlockScans {
    function find(uint abs, uint end, bytes4 key) internal pure returns (uint) {
        while (abs < end) {
            (bytes4 current, uint len) = Blocks.header(abs);
            if (Sizes.Header + len > end - abs) revert Blocks.MalformedBlocks();
            if (current == key) return abs;
            abs += Sizes.Header + len;
        }
        return end;
    }

    function run(uint abs, uint limit, bytes4 key) internal pure returns (uint total, uint end) {
        end = abs;
        while (end < limit) {
            (bytes4 current, uint len) = Blocks.header(end);
            if (Sizes.Header + len > limit - end) revert Blocks.MalformedBlocks();
            if (current != key) break;
            end += Sizes.Header + len;
            unchecked { ++total; }
        }
    }
}

/// @dev Previous factory bodies and allocator, using unchanged production writers.
library PreviousBlockFactories {
    function allocate(uint len) private pure returns (bytes memory value) {
        value = new bytes(len + 32);
        assembly ("memory-safe") { mstore(value, len) }
    }

    function createCopy(bytes calldata payload) internal pure returns (bytes memory value) {
        uint len = max32(payload.length);
        value = allocate(Sizes.Header + len);
        Blocks.copy(value, 0, Keys.Bytes, payload);
    }

    function create(bytes memory payload) internal pure returns (bytes memory value) {
        uint len = max32(payload.length);
        value = allocate(Sizes.Header + len);
        Blocks.write(value, 0, Keys.Bytes, payload);
    }

    function createContextCopy(bytes calldata state, bytes calldata input) internal pure returns (bytes memory value) {
        uint len = max32(Sizes.B32 + 2 * Sizes.Header + state.length + input.length);
        value = allocate(len);
        Blocks.copyContext(value, 0, bytes32(uint(1)), state, input);
    }

    function createEmpty() internal pure returns (bytes memory value) {
        value = allocate(Sizes.Header);
        Blocks.writeEmpty(value, 0, Keys.Bytes);
    }

    function createBalance() internal pure returns (bytes memory value) {
        value = allocate(Sizes.Balance);
        Blocks.writeBalance(value, 0, bytes32(uint(1)), 2);
    }
}

contract TestBlocksOptimization {
    struct FactoryResult {
        uint usedGas;
        uint retained;
        bytes output;
        bool cleanTail;
        bool guardIntact;
    }
    function scan(bool optimized, bool findKey, bytes calldata input, uint start, uint length, bytes4 key)
        external view returns (uint usedGas, uint total, uint end)
    {
        uint abs;
        assembly ("memory-safe") { abs := input.offset }
        uint limit = abs + length;
        uint initial = gasleft();
        if (findKey) {
            end = optimized ? Blocks.find(abs + start, limit, key)
                : PreviousBlockScans.find(abs + start, limit, key);
        } else {
            if (optimized) (total, end) = Blocks.run(abs + start, limit, key);
            else (total, end) = PreviousBlockScans.run(abs + start, limit, key);
        }
        usedGas = initial - gasleft();
        end -= abs;
    }

    // 0 generic calldata, 1 generic memory, 2 context, 3 empty, 4 balance.
    function factory(bool optimized, uint kind, bytes calldata a, bytes calldata b)
        external view returns (FactoryResult memory result)
    {
        bytes memory output;
        bytes memory memoryInput = a;
        uint len = kind == 2 ? max32(Sizes.B32 + 2 * Sizes.Header + a.length + b.length)
            : kind == 3 ? Sizes.Header : kind == 4 ? Sizes.B64 : Sizes.Header + max32(a.length);
        uint start;
        uint memoryEnd;
        // Poison the free memory region and one guard word. Both strategies must
        // reserve the same footprint and overwrite every logical output byte.
        assembly ("memory-safe") {
            start := mload(0x40)
            memoryEnd := add(add(start, 0x40), and(add(len, 31), not(31)))
            for { let p := start } iszero(gt(p, memoryEnd)) { p := add(p, 32) } {
                mstore(p, not(0))
            }
        }
        uint initial = gasleft();
        if (kind == 0) output = optimized ? Blocks.createCopy(Keys.Bytes, a) : PreviousBlockFactories.createCopy(a);
        else if (kind == 1) output = optimized ? Blocks.create(Keys.Bytes, memoryInput) : PreviousBlockFactories.create(memoryInput);
        else if (kind == 2) output = optimized ? Blocks.createContextCopy(bytes32(uint(1)), a, b) : PreviousBlockFactories.createContextCopy(a, b);
        else if (kind == 3) output = optimized ? Blocks.createEmpty(Keys.Bytes) : PreviousBlockFactories.createEmpty();
        else output = optimized ? Blocks.createBalance(bytes32(uint(1)), 2) : PreviousBlockFactories.createBalance();
        result.usedGas = initial - gasleft();
        result.output = output;
        assembly ("memory-safe") {
            mstore(add(result, 32), sub(mload(0x40), start))
            mstore(add(result, 128), eq(mload(memoryEnd), not(0)))
            mstore(add(result, 96), 1)
            // new bytes(len + 32) guarantees the requested scratch bytes, not
            // unused alignment slack after them.
            let tailEnd := add(add(output, 64), len)
            for { let p := add(add(output, 32), len) } lt(p, tailEnd) { p := add(p, 1) } {
                if byte(0, mload(p)) { mstore(add(result, 96), 0) }
            }
        }
    }
}
