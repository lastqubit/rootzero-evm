// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Encoder, Logs, Execution, Executions} from "../Codec.sol";

abstract contract BalanceLogCompositionHarness {
    using Executions for Execution;
    function prepare(Execution memory, bytes32, uint, uint) internal pure virtual {}
    function one(Execution memory exec, uint codes, bytes32 asset, uint amount) internal virtual;
    function output(Execution memory) internal pure virtual returns (bytes memory) { return ""; }

    function measure(uint codes, bytes32 asset, uint amount, uint count)
        external returns (uint used, uint retainedBytes, bytes memory result, bytes memory guard)
    {
        guard = abi.encode(bytes32(type(uint).max), uint(0x1234));
        bytes32 beforeHash = keccak256(guard);
        Execution memory exec;
        prepare(exec, asset, amount, count);
        uint beforePointer;
        assembly ("memory-safe") { beforePointer := mload(0x40) }
        uint initial = gasleft();
        for (uint i; i < count; ++i) one(exec, codes, asset, amount);
        used = initial - gasleft();
        uint afterPointer;
        assembly ("memory-safe") { afterPointer := mload(0x40) }
        require(afterPointer >= beforePointer, "allocator moved backwards");
        retainedBytes = afterPointer - beforePointer;
        require(keccak256(guard) == beforeHash, "guard changed");
        result = output(exec);
        // A subsequent allocation must not observe corrupted allocator state.
        bytes memory afterLog = abi.encode(uint(0x5678), asset, amount);
        require(afterLog.length == 96, "allocation failed");
    }
}

contract BalanceLogCreate is BalanceLogCompositionHarness {
    function one(Execution memory, uint codes, bytes32 asset, uint amount) internal override {
        bytes memory data = Encoder.createBalance(asset, amount);
        Logs.mem(codes, Encoder.pos(data, 0), data.length);
    }
}

contract BalanceLogTemporary is BalanceLogCompositionHarness {
    function one(Execution memory, uint codes, bytes32 asset, uint amount) internal override {
        uint start;
        // Reserve an owned region across Solidity helper calls, then release it.
        // No allocation or pointer from this region escapes the helper.
        assembly ("memory-safe") {
            start := mload(0x40)
            mstore(0x40, add(start, 128))
            mstore(start, 0)
        }
        Encoder.writeBalanceAt(start + 32, asset, amount);
        Logs.mem(codes, start + 32, 72);
        assembly ("memory-safe") { mstore(0x40, start) }
    }
}

contract BalanceLogTemporaryDirect is BalanceLogCompositionHarness {
    function one(Execution memory, uint codes, bytes32 asset, uint amount) internal override {
        uint start;
        assembly ("memory-safe") {
            start := mload(0x40)
            mstore(0x40, add(start, 128))
            mstore(start, codes)
        }
        Encoder.writeBalanceAt(start + 32, asset, amount);
        assembly ("memory-safe") {
            log0(start, 104)
            mstore(0x40, start)
        }
    }
}

contract BalanceLogOutput is BalanceLogCompositionHarness {
    using Executions for Execution;
    function prepare(Execution memory exec, bytes32, uint, uint count) internal pure override {
        (exec.buffer, exec.output) = Encoder.init(72 * count);
    }
    function one(Execution memory exec, uint codes, bytes32 asset, uint amount) internal override {
        uint abs = exec.reserve(72);
        Encoder.writeBalanceAt(abs, asset, amount);
        Logs.mem(codes, abs, 72);
    }
    function output(Execution memory exec) internal pure override returns (bytes memory) {
        return exec.finish();
    }
}

contract BalanceLogExisting is BalanceLogCompositionHarness {
    using Executions for Execution;
    function prepare(Execution memory exec, bytes32 asset, uint amount, uint) internal pure override {
        (exec.buffer, exec.output) = Encoder.init(72);
        exec.outputBalance(asset, amount);
    }
    function one(Execution memory exec, uint codes, bytes32, uint) internal override {
        Logs.mem(codes, Encoder.pos(exec.buffer, 0), 72);
    }
    function output(Execution memory exec) internal pure override returns (bytes memory) {
        return exec.finish();
    }
}
