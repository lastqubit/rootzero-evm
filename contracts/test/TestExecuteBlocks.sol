// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Execute} from "../codec/Execute.sol";
import {Position} from "../core/Types.sol";
import {Cursors} from "../utils/Cursors.sol";

contract TestExecuteBlocks {
    function balanceOutput(uint count) external pure returns (bytes memory output) {
        uint abs;
        (abs, output) = Execute.allocateBalances(count);
        for (uint i; i < count; ++i) {
            abs = Execute.writeBalance(abs, bytes32(i + 1), type(uint).max - i);
        }
    }

    function inspectPositions(bytes memory source) external pure returns (
        Position memory first, Position memory second, bytes32 beforeHash, bytes32 afterHash, uint allocated
    ) {
        (uint abs, uint end) = Execute.bounds(source, 168);
        require(end - abs == 336);
        beforeHash = keccak256(source);
        uint free;
        assembly ("memory-safe") { free := mload(0x40) }
        first = Execute.unpackPositionMemory(abs);
        second = Execute.unpackPositionMemory(abs + 168);
        assembly ("memory-safe") { allocated := sub(mload(0x40), free) }
        first.amount = 0;
        first.counterparty = bytes32(uint(99));
        afterHash = keccak256(source);
    }

    function bounds(bytes calldata source, uint start, uint end, uint metadata, uint size)
        external pure returns (uint offset, uint length)
    {
        uint cur = Cursors.wrap(source[start:end]) | (metadata & ~uint(type(uint64).max));
        (uint abs, uint endAbs) = Execute.bounds(cur, size);
        assembly ("memory-safe") { offset := sub(abs, source.offset) }
        length = endAbs - abs;
    }
}
