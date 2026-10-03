// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Specs} from "../codec/Specs.sol";
import {Logs} from "../codec/Logs.sol";
import {Cursors} from "../utils/Cursors.sol";
import {STATE_KEY, INPUT_KEY, CONTEXT_KEY} from "../codec/Keys.sol";
import {INVALID_BLOCK} from "../utils/Errors.sol";
import {Execution, Executions} from "../execution/Execution.sol";

library PreviousExecutionPlan {
    using Blocks for uint;
    /// @notice Describe an endpoint's schemas, allocation metadata, and behavior.
    /// @dev Layout: [state key:4][input key:4][output key:4][source key:4]
    /// [source block size:4][output block size:4][source shift:1][lanes:1][reserved:5][flags:1].
    /// Source shift: 64 = state, 0 = input or none. Sizes include headers.
    /// Lane bits describe declared sources for metadata consumers; cursors carry no flags.
    /// Declared state takes precedence over input, including when supplied state is empty.
    function describe(uint state, uint input, uint output, uint8 flags) internal pure returns (uint descriptor) {
        uint32 stateKey = uint32(Specs.key(state));
        uint32 inputKey = uint32(Specs.key(input));
        uint source = stateKey != 0 ? state : input;
        descriptor |= uint(stateKey) << 224;
        descriptor |= uint(inputKey) << 192;
        descriptor |= uint(uint32(Specs.key(output))) << 160;
        descriptor |= uint(uint32(Specs.key(source))) << 128;
        descriptor |= Specs.blockSize(source) << 96;
        descriptor |= Specs.blockSize(output) << 64;
        descriptor |= uint(stateKey != 0 ? 64 : 0) << 56;
        descriptor |= uint((stateKey != 0 ? 1 : 0) | (inputKey != 0 ? 2 : 0)) << 48;
        descriptor |= flags;
    }


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

// Identical external ABI, immutable metadata, loop, and timers for both implementations.
abstract contract ExecutionPlanHarness {
    uint public immutable plan;
    constructor(uint value) { plan = value; }
    function open(Execution memory exec, bytes calldata context, uint budget) internal view virtual;
    function logs(uint state, uint input, bytes memory output) internal virtual;
    function measure(bytes calldata context, uint budget) external view returns (
        uint gasUsed, bytes32 account, uint remaining, uint inputCur, uint stateCur, uint outputCur, uint bufferSize
    ) {
        Execution memory exec;
        uint beforeGas = gasleft();
        open(exec, context, budget);
        gasUsed = beforeGas - gasleft();
        return (gasUsed, exec.account, exec.budget, exec.input, exec.state, exec.output, exec.buffer.length);
    }
    function run(bytes calldata context, uint budget) external returns (uint gasUsed, bytes memory output, uint credit) {
        uint beforeGas = gasleft();
        Execution memory exec;
        open(exec, context, budget);
        uint state = exec.state;
        uint input = exec.input;
        while (Executions.more(exec)) {
            uint blockCur;
            if (Cursors.more(exec.state)) {
                (blockCur, exec.state) = Blocks.take(exec.state);
                Executions.outputBlock(exec, blockCur);
            }
            if (Cursors.more(exec.input)) {
                (blockCur, exec.input) = Blocks.take(exec.input);
                Executions.outputBlock(exec, blockCur);
            }
        }
        output = Encoder.finish(exec.output, exec.buffer);
        credit = exec.budget;
        exec.budget = 0;
        logs(state, input, output);
        gasUsed = beforeGas - gasleft();
    }
}
contract ExecutionPlanCurrent is ExecutionPlanHarness {
    constructor(uint state, uint input, uint output, uint8 flags)
        ExecutionPlanHarness(PreviousExecutionPlan.describe(state, input, output, flags)) {}
    function open(Execution memory exec, bytes calldata context, uint budget) internal view override {
        PreviousExecutionPlan.openContext(exec, plan, budget, context);
    }
    function logs(uint state, uint input, bytes memory output) internal override {
        if (plan & 4 != 0) Logs.copy(123, state);
        if (plan & 8 != 0) Logs.copy(123, input);
        if (plan & 16 != 0) Logs.mem(123, Encoder.pos(output, 0), output.length);
    }
}
contract ExecutionPlanCandidate is ExecutionPlanHarness {
    constructor(uint state, uint input, uint output, uint8 flags)
        ExecutionPlanHarness(Executions.describe(state | (flags & 4 != 0 ? 1 : 0), input | (flags & 8 != 0 ? 1 : 0), output | (flags & 16 != 0 ? 1 : 0))) {}
    function open(Execution memory exec, bytes calldata context, uint budget) internal view override {
        Executions.openContext(exec, plan, budget, context);
    }
    function logs(uint state, uint input, bytes memory output) internal override {
        if (plan & 2 != 0) Logs.copy(123, state);
        if (plan & 4 != 0) Logs.copy(123, input);
        if (plan & 8 != 0) Logs.mem(123, Encoder.pos(output, 0), output.length);
    }
}
