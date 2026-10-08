// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs as PreviousLogs} from "./PreviousEventLogs.sol";

import {Logs, Encoder} from "../Codec.sol";
import {Cursors} from "../utils/Cursors.sol";

contract TestLogs {
    function memoryLogs(uint[] calldata codes, bytes memory data, uint offset, uint size, bool sharedEmpty)
        external returns (bytes memory)
    {
        if (sharedEmpty) { bytes memory empty; data = empty; }
        require(offset <= data.length && size <= data.length - offset, "invalid range");
        uint abs = Encoder.pos(data, offset);
        uint length = data.length;
        bytes32 hash = keccak256(data);
        uint pointer;
        uint prefix;
        uint zero;
        assembly ("memory-safe") {
            pointer := mload(0x40)
            prefix := mload(sub(abs, 32))
            zero := mload(0x60)
        }
        for (uint i; i < codes.length; ++i) PreviousLogs.mem(codes[i], abs, size);
        assembly ("memory-safe") {
            if iszero(and(eq(pointer, mload(0x40)),
                and(eq(prefix, mload(sub(abs, 32))), eq(zero, mload(0x60))))) { revert(0, 0) }
        }
        require(data.length == length && keccak256(data) == hash, "data changed");
        return data;
    }

    function calldataLogs(uint[] calldata codes, bytes calldata data, uint offset, uint size)
        external returns (bytes memory guard, bytes memory afterLog)
    {
        require(offset <= data.length && size <= data.length - offset, "invalid range");
        guard = abi.encode(uint(0x1234), bytes32(type(uint).max));
        bytes32 hash = keccak256(guard);
        uint abs;
        uint pointer;
        uint zero;
        assembly ("memory-safe") {
            abs := add(data.offset, offset)
            pointer := mload(0x40)
            zero := mload(0x60)
        }
        uint cur = Cursors.pack(abs, abs + size);
        for (uint i; i < codes.length; ++i) PreviousLogs.copy(codes[i], cur);
        assembly ("memory-safe") {
            if iszero(and(eq(pointer, mload(0x40)), eq(zero, mload(0x60)))) { revert(0, 0) }
        }
        require(keccak256(guard) == hash, "guard changed");
        // Allocate after the temporary log buffer; allocator users must still work.
        afterLog = abi.encode(uint(0x5678), data);
    }

    function emitBalance(bytes32 account, bytes32 asset, uint amount) external {
        Logs.balance(account, asset, amount);
    }

    function measureMem(uint codes, bytes memory data) external returns (uint used) {
        uint abs = Encoder.pos(data, 0);
        uint size = data.length;
        uint initial = gasleft();
        PreviousLogs.mem(codes, abs, size);
        used = initial - gasleft();
    }

    function measureCopy(uint codes, bytes calldata data) external returns (uint used) {
        uint abs;
        assembly ("memory-safe") { abs := data.offset }
        uint size = data.length;
        uint initial = gasleft();
        PreviousLogs.copy(codes, abs, size);
        used = initial - gasleft();
    }
}
