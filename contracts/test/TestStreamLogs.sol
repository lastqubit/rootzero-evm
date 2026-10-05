// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Logs, Encoder} from "../Codec.sol";

contract TestStreamLogs {
    event Ordinary(uint value);

    function emitMemoryWrap(uint prefix, bytes4 key, bytes memory source, bool sharedEmpty)
        external returns (bytes memory data)
    {
        if (!sharedEmpty) data = source;
        bytes32 beforeHash = keccak256(data);
        uint length = data.length;
        uint pointer;
        uint zero;
        assembly ("memory-safe") {
            pointer := mload(0x40)
            zero := mload(0x60)
            // Dirty scratch must not leak into either emitted record.
            mstore(pointer, not(0))
            mstore(add(pointer, 32), not(0))
        }
        Logs.memCopyWrap(prefix, key, data);
        Logs.memCopyWrap(prefix, key, data);
        uint afterPointer;
        uint afterZero;
        assembly ("memory-safe") {
            afterPointer := mload(0x40)
            afterZero := mload(0x60)
        }
        require(pointer == afterPointer && zero == afterZero, "memory changed");
        require(data.length == length && keccak256(data) == beforeHash, "data changed");
        emit Ordinary(7);
    }

    function emitStream(bytes32 id, bytes memory source, uint count, bool sharedEmpty, uint offset, uint size)
        external returns (bytes memory data)
    {
        if (!sharedEmpty) {
            // Force a nonzero guard word immediately before the bytes length.
            assembly ("memory-safe") {
                let ptr := mload(0x40)
                mstore(ptr, not(0))
                data := add(ptr, 32)
                let sourceSize := mload(source)
                mstore(data, sourceSize)
                mcopy(add(data, 32), add(source, 32), sourceSize)
                mstore(0x40, add(add(data, 32), and(add(sourceSize, 31), not(31))))
            }
        }
        require(offset <= data.length && size <= data.length - offset, "invalid range");
        uint abs = Encoder.pos(data, offset);
        bytes32 beforeHash = keccak256(data);
        uint length = data.length;
        uint pointer;
        uint guard;
        uint zero;
        assembly ("memory-safe") {
            pointer := mload(0x40)
            guard := mload(sub(data, 32))
            zero := mload(0x60)
        }
        for (uint i; i < count; ++i) Logs.stream(id, abs, size);
        uint afterPointer;
        uint afterGuard;
        uint afterZero;
        assembly ("memory-safe") {
            afterPointer := mload(0x40)
            afterGuard := mload(sub(data, 32))
            afterZero := mload(0x60)
        }
        require(pointer == afterPointer && guard == afterGuard && zero == afterZero, "memory changed");
        require(data.length == length && keccak256(data) == beforeHash, "data changed");
        emit Ordinary(7);
    }

    function measure(bytes32 id, bytes memory data, bool prefixed) external returns (uint used) {
        uint abs = Encoder.pos(data, 0);
        uint size = data.length;
        uint initial = gasleft();
        if (prefixed) Logs.stream(id, abs, size);
        else assembly ("memory-safe") { log1(add(data, 32), mload(data), id) }
        used = initial - gasleft();
    }
    /// @dev Scalar log scratch must preserve live allocations and allocator state.
    function emitScalars(uint codes, bytes32 subject, uint amount, bytes memory live) external {
        bytes32 digest = keccak256(live);
        uint beforeFree;
        assembly ("memory-safe") {
            beforeFree := mload(0x40)
            mstore(beforeFree, not(0))
            mstore(add(beforeFree, 32), not(0))
            mstore(add(beforeFree, 64), not(0))
            mstore(add(beforeFree, 96), not(0))
        }
        Logs.pipeline(subject, amount, codes);
        Logs.balance(subject, amount, codes);
        Logs.pipeline(subject, amount, codes);
        uint afterFree;
        uint zero;
        assembly ("memory-safe") {
            afterFree := mload(0x40)
            zero := mload(0x60)
        }
        require(beforeFree == afterFree && zero == 0 && digest == keccak256(live));
    }
}
