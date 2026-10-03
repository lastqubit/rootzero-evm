// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {Encoder} from "../codec/Encoder.sol";

import {Execution, Executions} from "../execution/Execution.sol";
import {Specs} from "../codec/Specs.sol";
import {Blocks} from "../codec/Blocks.sol";


/// @dev Benchmark only. Production allocation policy is unchanged.
contract TestBufferAllocation {
    using Executions for Execution;

    // strategy: 0 = production scan, 1 = lazy, 2/3/4 = 1x/2x/4x input bytes.
    // strategy: 5 = divisible source hint, otherwise production runCount.
    // strategy: 7 = current production descriptor and allocation.
    // strategy: 6 = always ceiling-divide by the source hint, never scan.
    // workload: 0 = equal size, 1 = expanding, 2/3 = BYTES to BALANCE,
    // 4 = sparse, 5 = unused, 6/7 = under/overestimates, 8 = zero hint.
    function measure(uint strategy, uint workload, bytes calldata input, uint repetitions)
        external view returns (uint usedGas, uint retained, uint outputLength, bytes32 digest)
    {
        uint descriptor = Executions.describe(
            Specs.Empty,
            workload == 2 || workload == 3 || workload >= 6 ? Specs.Bytes : Specs.AssetAmount,
            workload == 1 ? Specs.Position : Specs.Balance);
        // Artificial zero block size exercises lazy/fallback behavior.
        if (workload == 8) descriptor &= ~(uint(type(uint32).max) << 192);
        bytes memory output;
        uint startMemory;
        assembly ("memory-safe") { startMemory := mload(0x40) }
        uint startGas = gasleft();
        for (uint repetition; repetition < repetitions; ++repetition) {
            output = execute(strategy, workload, input, descriptor);
        }
        usedGas = startGas - gasleft();
        assembly ("memory-safe") { retained := sub(mload(0x40), startMemory) }
        outputLength = output.length;
        digest = keccak256(output);
    }

    function execute(uint strategy, uint workload, bytes calldata input, uint descriptor)
        private pure returns (bytes memory)
    {
        Execution memory exec;
        if (strategy == 7) {
            exec.openInput(descriptor, 0, input);
        } else {
            // Same decoder initialization as openInput, without the hint scan.
            uint cur;
            assembly ("memory-safe") {
                cur := or(input.offset, shl(32, add(input.offset, input.length)))
            }
            exec.input = cur;
            uint capacity = strategy == 0 ? scannedCapacity(input, descriptor)
                : strategy == 6 ? ceilingCapacity(input.length, descriptor)
                : strategy == 5 ? hintedCapacity(input, descriptor)
                : strategy == 1 ? 0 : input.length * (1 << (strategy - 2));
            (exec.buffer, exec.output) = Encoder.init(capacity);
        }
        uint index;
        while (exec.more()) {
            bytes32 asset;
            uint amount;
            if (workload == 2 || workload == 3 || workload >= 6) {
                bytes calldata payload = Blocks.toBytes(exec.unpackBytes());
                asset = bytes32(uint(1));
                amount = payload.length;
            } else {
                (asset, amount) = exec.unpackAssetAmount();
            }
            if (workload == 1) {
                exec.outputPosition(asset, amount, bytes32(uint(2)), amount, bytes32(0));
            } else if (workload != 5 && (workload != 4 || index % 8 == 0)) {
                exec.outputBalance(asset, amount);
            }
            ++index;
        }
        return exec.finish();
    }

    function hintedCapacity(bytes calldata input, uint descriptor) private pure returns (uint) {
        uint blockSize = uint32(descriptor >> 192);
        uint count;
        if (blockSize != 0 && input.length % blockSize == 0) {
            count = input.length / blockSize;
        } else {
            uint start;
            assembly ("memory-safe") { start := input.offset }
            count = LegacyBlocks.runCount(start, start + input.length, bytes4(uint32(descriptor >> 224)));
        }
        return count * uint32(descriptor >> 160);
    }

    function ceilingCapacity(uint length, uint descriptor) private pure returns (uint) {
        uint blockSize = uint32(descriptor >> 192);
        if (blockSize == 0) return 0;
        uint count = length / blockSize;
        if (length % blockSize != 0) ++count;
        return count * uint32(descriptor >> 160);
    }

    function scannedCapacity(bytes calldata input, uint descriptor) private pure returns (uint) {
        uint start;
        assembly ("memory-safe") { start := input.offset }
        return LegacyBlocks.runCount(start, start + input.length, bytes4(uint32(descriptor >> 224))) * uint32(descriptor >> 160);
    }

}
