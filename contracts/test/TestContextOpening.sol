// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Cursors} from "../utils/Cursors.sol";
import {STATE_KEY, INPUT_KEY, CONTEXT_KEY} from "../codec/Keys.sol";
import {INVALID_BLOCK, InvalidBlock} from "../utils/Errors.sol";
import {Execution} from "../execution/Execution.sol";

// Frozen opening algorithm and shared-unpacker candidate, with identical capacity calculation.
library PreviousContextOpening {
    using Blocks for uint;
    function outputCapacity(uint input, uint state, uint descriptor) private pure returns (uint capacity) {
        if (uint32(descriptor >> 160) == 0) return 0;
        uint count = 1;
        bytes4 key = bytes4(uint32(descriptor >> 128));
        if (key != bytes4(0)) {
            uint source = uint8(descriptor >> 56) == 64 ? state : input;
            uint abs = uint32(source);
            uint end = uint32(source >> 32);
            uint blockSize = uint32(descriptor >> 96);
            if (blockSize != 0 && (end - abs) % blockSize == 0) {
                count = (end - abs) / blockSize;
            } else {
                count = source.runCount(key);
            }
        }
        // Source positions and block sizes are uint32. Both counting paths
        // produce at most uint32.max blocks, so the product fits uint64.
        // Encoder.init enforces the uint32 capacity limit.
        unchecked {
            capacity = count * uint32(descriptor >> 64);
        }
    }
    function openContext(Execution memory exec, uint descriptor, uint budget, bytes calldata context) internal pure {
        uint input;
        uint state;
        bytes32 account;
        // A genuine bounded calldata slice plus uint32 nested lengths cannot
        // overflow uint256 offsets. The tail check rejects subtraction underflow;
        // the final boundary check confines both lanes to the supplied slice.
        // Keep this local: unpackContext also accepts arbitrary absolute offsets.
        assembly ("memory-safe") {
            function fail(selector) {
                mstore(0, selector)
                revert(28, 4)
            }
            let start := context.offset
            let head := calldataload(start)
            if iszero(eq(shr(224, head), CONTEXT_KEY)) {
                fail(INVALID_BLOCK)
            }
            let limit := add(add(start, 8), and(shr(192, head), 0xffffffff))
            account := calldataload(add(start, 8))
            let stateHeader := add(start, 40)
            head := calldataload(stateHeader)
            if iszero(eq(shr(224, head), STATE_KEY)) {
                fail(INVALID_BLOCK)
            }
            let stateStart := add(stateHeader, 8)
            let stateEnd := add(stateStart, and(shr(192, head), 0xffffffff))
            let inputStart := add(stateEnd, 8)
            let inputLength := sub(limit, inputStart)
            // Match unpackTailBytes, including underflow and exact header length.
            if or(
                gt(inputLength, 0xffffffff),
                iszero(eq(shr(192, calldataload(stateEnd)), or(shl(32, INPUT_KEY), inputLength)))
            ) {
                fail(INVALID_BLOCK)
            }
            if iszero(eq(limit, add(start, context.length))) {
                fail(INVALID_BLOCK)
            }
            input := or(inputStart, shl(32, limit))
            state := or(stateStart, shl(32, stateEnd))
        }
        exec.account = account;
        exec.budget = budget;
        exec.input = input;
        exec.state = state;
        (exec.buffer, exec.output) = Encoder.init(outputCapacity(input, state, descriptor));
    }
}
library SharedContextOpening {
    using Blocks for uint;
    function outputCapacity(uint input, uint state, uint descriptor) private pure returns (uint capacity) {
        if (uint32(descriptor >> 160) == 0) return 0;
        uint count = 1;
        bytes4 key = bytes4(uint32(descriptor >> 128));
        if (key != bytes4(0)) {
            uint source = uint8(descriptor >> 56) == 64 ? state : input;
            uint abs = uint32(source);
            uint end = uint32(source >> 32);
            uint blockSize = uint32(descriptor >> 96);
            if (blockSize != 0 && (end - abs) % blockSize == 0) {
                count = (end - abs) / blockSize;
            } else {
                count = source.runCount(key);
            }
        }
        // Source positions and block sizes are uint32. Both counting paths
        // produce at most uint32.max blocks, so the product fits uint64.
        // Encoder.init enforces the uint32 capacity limit.
        unchecked {
            capacity = count * uint32(descriptor >> 64);
        }
    }
    function openContext(Execution memory exec, uint descriptor, uint budget, bytes calldata context) internal pure {
        uint nextCur;
        (exec.account, exec.state, exec.input, nextCur) = Blocks.unpackContext(Cursors.wrap(context));
        Cursors.expectEnd(nextCur);
        exec.budget = budget;
        (exec.buffer, exec.output) = Encoder.init(outputCapacity(exec.input, exec.state, descriptor));
    }
}
contract ContextOpeningPrevious {
    function measure(bytes calldata context, uint descriptor, uint budget) external view returns (
        uint gasUsed, bytes32 account, uint remaining, uint inputCur, uint stateCur, uint outputCur, uint bufferSize
    ) {
        Execution memory exec;
        uint beforeGas = gasleft();
        PreviousContextOpening.openContext(exec, descriptor, budget, context);
        gasUsed = beforeGas - gasleft();
        return (gasUsed, exec.account, exec.budget, exec.input, exec.state, exec.output, exec.buffer.length);
    }
}
contract ContextOpeningShared {
    function measure(bytes calldata context, uint descriptor, uint budget) external view returns (
        uint gasUsed, bytes32 account, uint remaining, uint inputCur, uint stateCur, uint outputCur, uint bufferSize
    ) {
        Execution memory exec;
        uint beforeGas = gasleft();
        SharedContextOpening.openContext(exec, descriptor, budget, context);
        gasUsed = beforeGas - gasleft();
        return (gasUsed, exec.account, exec.budget, exec.input, exec.state, exec.output, exec.buffer.length);
    }
}
