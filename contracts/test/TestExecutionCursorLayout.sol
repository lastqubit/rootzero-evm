// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
// Frozen packed layout for the benchmark baseline.
struct Execution {
    bytes32 account;
    uint budget;
    uint decoders;
    uint output;
    bytes buffer;
}
import {Blocks} from "../codec/Blocks.sol";
import {Headers} from "../codec/Headers.sol";

import {Execution as SplitCursorExecution} from "../execution/Execution.sol";

/// @dev Layout-only comparison using Blocks on both sides. No production migration.
contract ExecutionCursorLayoutPacked {
    function inputBalance(Execution memory exec) private pure returns (bytes32 asset, uint amount) {
        (asset, amount, exec.decoders) = Blocks.unpackBalance(exec.decoders);
    }
    function stateBalance(Execution memory exec) private pure returns (bytes32 asset, uint amount) {
        uint decoders = exec.decoders;
        uint cur = decoders >> 64;
        (asset, amount, cur) = Blocks.unpackBalance(cur);
        exec.decoders = (decoders & uint(type(uint64).max)) | (cur << 64);
    }
    function constraints(Execution memory exec, bytes32 asset, uint amount) private pure {
        exec.decoders = Blocks.expectBalanceConstraints(exec.decoders, asset, amount);
    }
    function saveConstraints(Execution memory exec) private pure returns (uint payloadCur) {
        (payloadCur, exec.decoders) = Blocks.unpackFixed(exec.decoders, Headers.BalanceConstraints);
    }
    function moreInput(Execution memory exec) private pure returns (bool) {
        return uint32(exec.decoders) < uint32(exec.decoders >> 32);
    }
    function moreState(Execution memory exec) private pure returns (bool) {
        return uint32(exec.decoders >> 64) < uint32(exec.decoders >> 96);
    }
    function run(Execution memory exec, uint mode) private pure returns (uint count) {
        if (mode == 0) {
            while (moreInput(exec)) {
                (bytes32 asset, uint amount) = inputBalance(exec);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
        } else if (mode == 1) {
            while (moreState(exec)) {
                (bytes32 asset, uint amount) = stateBalance(exec);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
        } else if (mode == 2) {
            while (moreInput(exec)) {
                (bytes32 asset, uint amount) = stateBalance(exec);
                constraints(exec, asset, amount);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
            require(!moreState(exec));
        } else {
            while (moreInput(exec)) {
                // Parse and save the constraint, run representative hook arithmetic,
                // then check the resulting amount against the saved payload.
                uint payloadCur = saveConstraints(exec);
                (bytes32 asset, uint amount) = stateBalance(exec);
                unchecked { amount += 1; }
                Blocks.checkBalanceConstraints(uint32(payloadCur), asset, amount);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
            require(!moreState(exec));
        }
    }
    function measure(bytes calldata input, bytes calldata state, uint mode, bool includeSetup, uint flags, uint seed)
        external view returns (uint gasUsed, uint checksum, uint count, uint inputCur, uint stateCur)
    {
        require(mode < 4 && flags < 4);
        uint beforeGas = gasleft();
        uint inputBase;
        uint stateBase;
        assembly ("memory-safe") { inputBase := input.offset stateBase := state.offset }
        inputCur = inputBase | ((inputBase + input.length) << 32);
        stateCur = stateBase | ((stateBase + state.length) << 32);
        Execution memory exec = Execution(bytes32(seed), seed, inputCur | (stateCur << 64) | (flags << 128), 7, new bytes(0));
        if (!includeSetup) beforeGas = gasleft();
        count = run(exec, mode);
        gasUsed = beforeGas - gasleft();
        unchecked { checksum = uint(exec.account) + exec.budget + exec.output + exec.buffer.length; }
        uint decoders = exec.decoders;
        inputCur = uint64(decoders) | (((decoders >> 129) & 1) << 64);
        stateCur = uint64(decoders >> 64) | (((decoders >> 128) & 1) << 64);
    }
}

/// @dev Layout-only comparison using Blocks on both sides. No production migration.
contract ExecutionCursorLayoutSplit {
    function inputBalance(SplitCursorExecution memory exec) private pure returns (bytes32 asset, uint amount) {
        (asset, amount, exec.input) = Blocks.unpackBalance(exec.input);
    }
    function stateBalance(SplitCursorExecution memory exec) private pure returns (bytes32 asset, uint amount) {
        (asset, amount, exec.state) = Blocks.unpackBalance(exec.state);
    }
    function constraints(SplitCursorExecution memory exec, bytes32 asset, uint amount) private pure {
        exec.input = Blocks.expectBalanceConstraints(exec.input, asset, amount);
    }
    function saveConstraints(SplitCursorExecution memory exec) private pure returns (uint payloadCur) {
        (payloadCur, exec.input) = Blocks.unpackFixed(exec.input, Headers.BalanceConstraints);
    }
    function moreInput(SplitCursorExecution memory exec) private pure returns (bool) {
        return uint32(exec.input) < uint32(exec.input >> 32);
    }
    function moreState(SplitCursorExecution memory exec) private pure returns (bool) {
        return uint32(exec.state) < uint32(exec.state >> 32);
    }
    function run(SplitCursorExecution memory exec, uint mode) private pure returns (uint count) {
        if (mode == 0) {
            while (moreInput(exec)) {
                (bytes32 asset, uint amount) = inputBalance(exec);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
        } else if (mode == 1) {
            while (moreState(exec)) {
                (bytes32 asset, uint amount) = stateBalance(exec);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
        } else if (mode == 2) {
            while (moreInput(exec)) {
                (bytes32 asset, uint amount) = stateBalance(exec);
                constraints(exec, asset, amount);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
            require(!moreState(exec));
        } else {
            while (moreInput(exec)) {
                // Parse and save the constraint, run representative hook arithmetic,
                // then check the resulting amount against the saved payload.
                uint payloadCur = saveConstraints(exec);
                (bytes32 asset, uint amount) = stateBalance(exec);
                unchecked { amount += 1; }
                Blocks.checkBalanceConstraints(uint32(payloadCur), asset, amount);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
            require(!moreState(exec));
        }
    }
    function measure(bytes calldata input, bytes calldata state, uint mode, bool includeSetup, uint flags, uint seed)
        external view returns (uint gasUsed, uint checksum, uint count, uint inputCur, uint stateCur)
    {
        require(mode < 4 && flags < 4);
        uint beforeGas = gasleft();
        uint inputBase;
        uint stateBase;
        assembly ("memory-safe") { inputBase := input.offset stateBase := state.offset }
        inputCur = inputBase | ((inputBase + input.length) << 32);
        stateCur = stateBase | ((stateBase + state.length) << 32);
        SplitCursorExecution memory exec = SplitCursorExecution(bytes32(seed), seed, inputCur | ((flags >> 1) << 64), stateCur | ((flags & 1) << 64), 7, new bytes(0));
        if (!includeSetup) beforeGas = gasleft();
        count = run(exec, mode);
        gasUsed = beforeGas - gasleft();
        unchecked { checksum = uint(exec.account) + exec.budget + exec.output + exec.buffer.length; }
        inputCur = exec.input;
        stateCur = exec.state;
    }
}

contract ExecutionCursorLayoutPackedPosition {
    function inputBalance(Execution memory exec) private pure returns (bytes32 asset, uint amount) {
        (asset, amount, exec.decoders) = Blocks.unpackBalance(exec.decoders);
    }
    function stateBalance(Execution memory exec) private pure returns (bytes32 asset, uint amount) {
        uint decoders = exec.decoders;
        uint cur = decoders >> 64;
        (asset, amount, cur) = Blocks.unpackBalance(cur);
        exec.decoders = (decoders & ~(uint(type(uint32).max) << 64)) | (uint(uint32(cur)) << 64);
    }
    function constraints(Execution memory exec, bytes32 asset, uint amount) private pure {
        exec.decoders = Blocks.expectBalanceConstraints(exec.decoders, asset, amount);
    }
    function saveConstraints(Execution memory exec) private pure returns (uint payloadCur) {
        (payloadCur, exec.decoders) = Blocks.unpackFixed(exec.decoders, Headers.BalanceConstraints);
    }
    function moreInput(Execution memory exec) private pure returns (bool) {
        return uint32(exec.decoders) < uint32(exec.decoders >> 32);
    }
    function moreState(Execution memory exec) private pure returns (bool) {
        return uint32(exec.decoders >> 64) < uint32(exec.decoders >> 96);
    }
    function run(Execution memory exec, uint mode) private pure returns (uint count) {
        if (mode == 0) {
            while (moreInput(exec)) {
                (bytes32 asset, uint amount) = inputBalance(exec);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
        } else if (mode == 1) {
            while (moreState(exec)) {
                (bytes32 asset, uint amount) = stateBalance(exec);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
        } else if (mode == 2) {
            while (moreInput(exec)) {
                (bytes32 asset, uint amount) = stateBalance(exec);
                constraints(exec, asset, amount);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
            require(!moreState(exec));
        } else {
            while (moreInput(exec)) {
                // Parse and save the constraint, run representative hook arithmetic,
                // then check the resulting amount against the saved payload.
                uint payloadCur = saveConstraints(exec);
                (bytes32 asset, uint amount) = stateBalance(exec);
                unchecked { amount += 1; }
                Blocks.checkBalanceConstraints(uint32(payloadCur), asset, amount);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
            require(!moreState(exec));
        }
    }
    function measure(bytes calldata input, bytes calldata state, uint mode, bool includeSetup, uint flags, uint seed)
        external view returns (uint gasUsed, uint checksum, uint count, uint inputCur, uint stateCur)
    {
        require(mode < 4 && flags < 4);
        uint beforeGas = gasleft();
        uint inputBase;
        uint stateBase;
        assembly ("memory-safe") { inputBase := input.offset stateBase := state.offset }
        inputCur = inputBase | ((inputBase + input.length) << 32);
        stateCur = stateBase | ((stateBase + state.length) << 32);
        Execution memory exec = Execution(bytes32(seed), seed, inputCur | (stateCur << 64) | (flags << 128), 7, new bytes(0));
        if (!includeSetup) beforeGas = gasleft();
        count = run(exec, mode);
        gasUsed = beforeGas - gasleft();
        unchecked { checksum = uint(exec.account) + exec.budget + exec.output + exec.buffer.length; }
        uint decoders = exec.decoders;
        inputCur = uint64(decoders) | (((decoders >> 129) & 1) << 64);
        stateCur = uint64(decoders >> 64) | (((decoders >> 128) & 1) << 64);
    }
}

contract ExecutionCursorLayoutPackedDelta {
    function inputBalance(Execution memory exec) private pure returns (bytes32 asset, uint amount) {
        (asset, amount, exec.decoders) = Blocks.unpackBalance(exec.decoders);
    }
    function stateBalance(Execution memory exec) private pure returns (bytes32 asset, uint amount) {
        uint decoders = exec.decoders;
        uint cur = decoders >> 64;
        (asset, amount, cur) = Blocks.unpackBalance(cur);
        unchecked { exec.decoders = decoders + ((uint(uint32(cur)) - uint32(decoders >> 64)) << 64); }
    }
    function constraints(Execution memory exec, bytes32 asset, uint amount) private pure {
        exec.decoders = Blocks.expectBalanceConstraints(exec.decoders, asset, amount);
    }
    function saveConstraints(Execution memory exec) private pure returns (uint payloadCur) {
        (payloadCur, exec.decoders) = Blocks.unpackFixed(exec.decoders, Headers.BalanceConstraints);
    }
    function moreInput(Execution memory exec) private pure returns (bool) {
        return uint32(exec.decoders) < uint32(exec.decoders >> 32);
    }
    function moreState(Execution memory exec) private pure returns (bool) {
        return uint32(exec.decoders >> 64) < uint32(exec.decoders >> 96);
    }
    function run(Execution memory exec, uint mode) private pure returns (uint count) {
        if (mode == 0) {
            while (moreInput(exec)) {
                (bytes32 asset, uint amount) = inputBalance(exec);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
        } else if (mode == 1) {
            while (moreState(exec)) {
                (bytes32 asset, uint amount) = stateBalance(exec);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
        } else if (mode == 2) {
            while (moreInput(exec)) {
                (bytes32 asset, uint amount) = stateBalance(exec);
                constraints(exec, asset, amount);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
            require(!moreState(exec));
        } else {
            while (moreInput(exec)) {
                // Parse and save the constraint, run representative hook arithmetic,
                // then check the resulting amount against the saved payload.
                uint payloadCur = saveConstraints(exec);
                (bytes32 asset, uint amount) = stateBalance(exec);
                unchecked { amount += 1; }
                Blocks.checkBalanceConstraints(uint32(payloadCur), asset, amount);
                unchecked { exec.budget += uint(asset) + amount; ++exec.output; ++count; }
            }
            require(!moreState(exec));
        }
    }
    function measure(bytes calldata input, bytes calldata state, uint mode, bool includeSetup, uint flags, uint seed)
        external view returns (uint gasUsed, uint checksum, uint count, uint inputCur, uint stateCur)
    {
        require(mode < 4 && flags < 4);
        uint beforeGas = gasleft();
        uint inputBase;
        uint stateBase;
        assembly ("memory-safe") { inputBase := input.offset stateBase := state.offset }
        inputCur = inputBase | ((inputBase + input.length) << 32);
        stateCur = stateBase | ((stateBase + state.length) << 32);
        Execution memory exec = Execution(bytes32(seed), seed, inputCur | (stateCur << 64) | (flags << 128), 7, new bytes(0));
        if (!includeSetup) beforeGas = gasleft();
        count = run(exec, mode);
        gasUsed = beforeGas - gasleft();
        unchecked { checksum = uint(exec.account) + exec.budget + exec.output + exec.buffer.length; }
        uint decoders = exec.decoders;
        inputCur = uint64(decoders) | (((decoders >> 129) & 1) << 64);
        stateCur = uint64(decoders >> 64) | (((decoders >> 128) & 1) << 64);
    }
}
