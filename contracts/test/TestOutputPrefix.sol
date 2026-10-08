// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs as PreviousLogs} from "./PreviousEventLogs.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Logs} from "../codec/Logs.sol";
import {ValueOverflow} from "../utils/Errors.sol";

// Frozen buffer primitives before adding the leading event-prefix word.
// OutputPrefixCandidate below exercises the production allocator and memWrap.
library PreviousPrefixEncoder {
    function allocate(uint size) internal pure returns (bytes memory value) {
        if (size > type(uint32).max) revert ValueOverflow();
        assembly ("memory-safe") {
            value := mload(0x40)
            let abs := add(value, 32)
            mstore(value, size)
            mstore(add(abs, size), 0)
            mstore(0x40, add(abs, and(add(size, 31), not(31))))
        }
    }
    function pos(bytes memory dst, uint i) internal pure returns (uint abs) {
        assembly ("memory-safe") {
            abs := add(add(dst, 32), i)
        }
    }
    function grow(bytes memory dst, uint written, uint capacity) internal pure returns (bytes memory value) {
        assembly ("memory-safe") {
            value := mload(0x40)
            let padded := add(and(add(capacity, 31), not(31)), 32)
            mstore(value, padded)
            mstore(0x40, add(add(value, 32), padded))
            mcopy(add(value, 32), add(dst, 32), written)
        }
    }
    function grow(uint cur, bytes memory dst, uint size) private pure returns (bytes memory value, uint nextCur) {
        uint written = uint32(cur);
        uint capacity = uint32(cur >> 32);
        uint required = written + size;
        if (required > type(uint32).max) revert ValueOverflow();
        unchecked {
            capacity = capacity == 0 ? 64 : capacity * 2;
            while (capacity < required) capacity *= 2;
        }
        if (capacity > type(uint32).max) revert ValueOverflow();
        nextCur = (cur & ~(uint(type(uint32).max) << 32)) | (capacity << 32);
        value = grow(dst, written, capacity);
    }
    function init(uint capacity) internal pure returns (bytes memory dst, uint cur) {
        if (capacity > type(uint32).max) revert ValueOverflow();
        cur = capacity << 32;
        bytes memory empty;
        dst = grow(empty, 0, capacity);
    }
    function reserve(
        uint cur,
        bytes memory dst,
        uint size
    ) internal pure returns (bytes memory value, uint abs, uint nextCur) {
        uint available;
        unchecked {
            available = uint32(cur >> 32) - uint(uint32(cur));
        }
        if (size > available) (dst, cur) = grow(cur, dst, size);
        abs = pos(dst, uint32(cur));
        unchecked {
            nextCur = cur + size;
        }
        value = dst;
    }
    function finish(uint cur, bytes memory dst) internal pure returns (bytes memory value) {
        uint written = uint32(cur);
        assembly ("memory-safe") {
            mstore(dst, written)
            mstore(add(add(dst, 32), written), 0)
        }
        value = dst;
    }
}

library OutputWrapCandidate {
    uint constant OutputKey = uint32(bytes4(keccak256("#output")));
    // Requires an owned leading word and a finished buffer of uint32 length.
    function memWrap(uint id, bytes memory output) internal {
        uint key = OutputKey;
        assembly ("memory-safe") {
            let prefixWord := sub(output, 32)
            let saved := mload(prefixWord)
            let size := mload(output)
            mstore(output, or(shl(32, key), size))
            mstore(sub(output, 8), id)
            log0(sub(output, 8), add(size, 40))
            mstore(prefixWord, saved)
            mstore(output, size)
        }
    }
    // Same event format, but usable with the current allocator by copying.
    function copyWrap(uint id, bytes memory output) internal {
        uint key = OutputKey;
        assembly ("memory-safe") {
            let start := mload(0x40)
            let size := mload(output)
            mstore(add(start, 8), or(shl(32, key), size))
            mstore(start, id)
            mcopy(add(start, 40), add(output, 32), size)
            log0(start, add(size, 40))
        }
    }
}

contract OutputPrefixCurrent {
    function measure(bytes calldata blockData, uint count, uint capacity, uint mode, bool interleave)
        external returns (uint buildGas, uint memoryBytes, uint logGas, bytes memory output)
    {
        uint startMemory;
        assembly ("memory-safe") { startMemory := mload(0x40) }
        uint startGas = gasleft();
        (bytes memory buffer, uint cur) = PreviousPrefixEncoder.init(capacity);
        bytes memory neighbor;
        for (uint i; i < count; ++i) {
            uint abs;
            (buffer, abs, cur) = PreviousPrefixEncoder.reserve(cur, buffer, blockData.length);
            assembly ("memory-safe") { calldatacopy(abs, blockData.offset, blockData.length) }
            if (interleave) neighbor = abi.encode(i, bytes32(type(uint).max));
        }
        output = PreviousPrefixEncoder.finish(cur, buffer);
        buildGas = startGas - gasleft();
        assembly ("memory-safe") { memoryBytes := sub(mload(0x40), startMemory) }
        logGas = verifyLog(output, neighbor, mode);
    }
    // Transient measurement via memory return, not contract storage.
    function allocate(bytes calldata data, uint mode) external returns (uint buildGas, uint memoryBytes, uint logGas, bytes memory output) {
        uint startMemory;
        assembly ("memory-safe") { startMemory := mload(0x40) }
        uint startGas = gasleft();
        output = PreviousPrefixEncoder.allocate(data.length);
        assembly ("memory-safe") { calldatacopy(add(output, 32), data.offset, data.length) }
        buildGas = startGas - gasleft();
        assembly ("memory-safe") { memoryBytes := sub(mload(0x40), startMemory) }
        bytes memory neighbor = abi.encode(uint(123), bytes32(type(uint).max));
        logGas = verifyLog(output, neighbor, mode);
    }
    function verifyLog(bytes memory output, bytes memory neighbor, uint mode) private returns (uint used) {

        bytes32 beforeOutput = keccak256(output);
        bytes32 beforeNeighbor = keccak256(neighbor);
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        uint beforeGas = gasleft();
        if (mode == 1) PreviousLogs.mem(123, PreviousPrefixEncoder.pos(output, 0), output.length);
        else if (mode == 2) OutputWrapCandidate.copyWrap(123, output);
        used = beforeGas - gasleft();
        uint afterMemory;
        assembly ("memory-safe") { afterMemory := mload(0x40) }
        require(afterMemory == beforeMemory && keccak256(output) == beforeOutput && keccak256(neighbor) == beforeNeighbor);

        // Future allocations must remain safe too.
        bytes memory next = abi.encode(uint(456), uint(789));
        require(next.length == 64 && keccak256(output) == beforeOutput);
    }
}

contract OutputPrefixCandidate {
    function measure(bytes calldata blockData, uint count, uint capacity, uint mode, bool interleave)
        external returns (uint buildGas, uint memoryBytes, uint logGas, bytes memory output)
    {
        uint startMemory;
        assembly ("memory-safe") { startMemory := mload(0x40) }
        uint startGas = gasleft();
        (bytes memory buffer, uint cur) = Encoder.init(capacity);
        bytes memory neighbor;
        for (uint i; i < count; ++i) {
            uint abs;
            (buffer, abs, cur) = Encoder.reserve(cur, buffer, blockData.length);
            assembly ("memory-safe") { calldatacopy(abs, blockData.offset, blockData.length) }
            if (interleave) neighbor = abi.encode(i, bytes32(type(uint).max));
        }
        output = Encoder.finish(cur, buffer);
        buildGas = startGas - gasleft();
        assembly ("memory-safe") { memoryBytes := sub(mload(0x40), startMemory) }
        logGas = verifyLog(output, neighbor, mode);
    }
    // Transient measurement via memory return, not contract storage.
    function allocate(bytes calldata data, uint mode) external returns (uint buildGas, uint memoryBytes, uint logGas, bytes memory output) {
        uint startMemory;
        assembly ("memory-safe") { startMemory := mload(0x40) }
        uint startGas = gasleft();
        output = Encoder.allocate(data.length);
        assembly ("memory-safe") { calldatacopy(add(output, 32), data.offset, data.length) }
        buildGas = startGas - gasleft();
        assembly ("memory-safe") { memoryBytes := sub(mload(0x40), startMemory) }
        bytes memory neighbor = abi.encode(uint(123), bytes32(type(uint).max));
        logGas = verifyLog(output, neighbor, mode);
    }
    function verifyLog(bytes memory output, bytes memory neighbor, uint mode) private returns (uint used) {
        assembly ("memory-safe") { mstore(sub(output, 32), not(0)) }
        bytes32 beforeOutput = keccak256(output);
        bytes32 beforeNeighbor = keccak256(neighbor);
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        uint beforeGas = gasleft();
        if (mode == 1) PreviousLogs.mem(123, Encoder.pos(output, 0), output.length);
        else if (mode == 2) PreviousLogs.memWrap(123, bytes4(keccak256("#output")), output);
        used = beforeGas - gasleft();
        uint afterMemory;
        assembly ("memory-safe") { afterMemory := mload(0x40) }
        require(afterMemory == beforeMemory && keccak256(output) == beforeOutput && keccak256(neighbor) == beforeNeighbor);
        uint restored;
        assembly ("memory-safe") { restored := mload(sub(output, 32)) }
        require(restored == type(uint).max);
        // Future allocations must remain safe too.
        bytes memory next = abi.encode(uint(456), uint(789));
        require(next.length == 64 && keccak256(output) == beforeOutput);
    }
}
