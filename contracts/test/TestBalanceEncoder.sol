// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {ReservedBlockEncoder} from "./ReservedBlockEncoder.sol";
import {Encoder} from "../codec/Encoder.sol";

import {Execution, Executions} from "../execution/Execution.sol";

abstract contract BalanceEncoderHarness {
    function write(bytes memory dst, uint i, bytes32 asset, uint amount) internal pure virtual returns (uint);
    function create(bytes32 asset, uint amount) internal pure virtual returns (bytes memory);

    function inspect(bytes32 asset, uint amount, uint offset) external pure returns (bytes memory created, bytes memory dst) {
        created = create(asset, amount);
        dst = new bytes(offset + 72 + 32);
        for (uint j; j < dst.length; ++j) dst[j] = 0xef;
        require(write(dst, offset, asset, amount) == offset + 72);
    }

    function measure(bytes32 asset, uint amount, uint count, bool factory) external view returns (uint used, uint allocated, bytes memory output) {
        if (!factory) output = new bytes(72 * count);
        uint initialMemory;
        assembly ("memory-safe") { initialMemory := mload(0x40) }
        uint initialGas = gasleft();
        if (factory) {
            for (uint j; j < count; ++j) output = create(asset, amount);
        } else {
            uint i;
            for (uint j; j < count; ++j) i = write(output, i, asset, amount);
        }
        used = initialGas - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), initialMemory) }
    }
}

contract TestBalanceEncoderPrevious is BalanceEncoderHarness {
    function write(bytes memory dst, uint i, bytes32 asset, uint amount) internal pure override returns (uint) {
        LegacyBlocks.writeBalance(dst, i, asset, amount);
        unchecked { return i + 72; }
    }
    function create(bytes32 asset, uint amount) internal pure override returns (bytes memory) {
        return LegacyBlocks.createBalance(asset, amount);
    }
}

contract TestBalanceEncoder is BalanceEncoderHarness {
    function write(bytes memory dst, uint i, bytes32 asset, uint amount) internal pure override returns (uint) {
        return ReservedBlockEncoder.writeBalance(dst, i, asset, amount);
    }
    function create(bytes32 asset, uint amount) internal pure override returns (bytes memory) {
        return Encoder.createBalance(asset, amount);
    }

    function append(bytes32 asset, uint amount, uint count, uint capacity) external pure returns (bytes memory) {
        (bytes memory writerBuffer, uint writer) = Encoder.init(capacity);
        for (uint j; j < count; ++j) (writerBuffer, writer) = Encoder.writeBalance(writer, writerBuffer, asset, amount);
        return Encoder.finish(writer, writerBuffer);
    }

    function mixed(bool execution, bool balanceFirst, uint capacity, bytes memory payload) external pure returns (bytes memory output, uint metadata) {
        if (execution) {
            Execution memory exec;
            (exec.buffer, exec.output) = Encoder.init(capacity);
            exec.output |= uint(0xabcdef) << 128;
            if (!balanceFirst) Executions.outputBytes(exec, payload);
            Executions.outputBalance(exec, bytes32(uint(1)), 123);
            Executions.outputBytes(exec, payload);
            Executions.outputBalance(exec, bytes32(uint(2)), 456);
            metadata = exec.output >> 128;
            output = Executions.finish(exec);
        } else {
            (bytes memory writerBuffer, uint writer) = Encoder.init(capacity);
            writer |= uint(0xabcdef) << 128;
            if (!balanceFirst) (writerBuffer, writer) = Encoder.writeBytes(writer, writerBuffer, payload);
            (writerBuffer, writer) = Encoder.writeBalance(writer, writerBuffer, bytes32(uint(1)), 123);
            (writerBuffer, writer) = Encoder.writeBytes(writer, writerBuffer, payload);
            (writerBuffer, writer) = Encoder.writeBalance(writer, writerBuffer, bytes32(uint(2)), 456);
            metadata = writer >> 128;
            output = Encoder.finish(writer, writerBuffer);
        }
    }
}
