// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyMemory} from "./LegacyMemory.sol";

import {PreviousMemoryBlocks as MemoryBlocks} from "./PreviousMemoryBlocks.sol";

import {Position} from "../core/Types.sol";

contract TestMemoryBlocks {
    using MemoryBlocks for uint;

    function balances(bytes memory source) external pure returns (bytes32 assets, uint total, uint consumed) {
        uint cur = MemoryBlocks.cursor(source);
        uint abs = uint32(cur);
        while (cur.more()) {
            bytes32 asset;
            uint amount;
            (asset, amount, cur) = cur.unpackBalance();
            assets ^= asset;
            total += amount;
        }
        consumed = uint32(cur) - abs;
    }

    function position(bytes memory source) external pure returns (Position memory value, uint consumed, bool more) {
        uint cur = MemoryBlocks.cursor(source);
        uint abs = uint32(cur);
        (value, cur) = cur.unpackPositionValue();
        return (value, uint32(cur) - abs, cur.more());
    }

    function comparePosition(bytes memory source) external pure returns (bool equal, bool independent) {
        uint cur = MemoryBlocks.cursor(source);
        Position memory oldValue = LegacyMemory.unpackPositionValue(uint32(cur));
        (Position memory value,) = cur.unpackPositionValue();
        equal = keccak256(abi.encode(value)) == keccak256(abi.encode(oldValue));
        bytes32 beforeHash = keccak256(source);
        value.amount ^= type(uint).max;
        independent = beforeHash == keccak256(source);
    }

    function bounded(bytes memory source, uint offset, uint length, uint metadata, bool positionBlock)
        external pure returns (uint consumed, uint remaining, uint preserved)
    {
        require(offset <= source.length && length <= source.length);
        uint base = uint32(MemoryBlocks.cursor(source));
        uint cur = (base + offset) | ((base + length) << 32) | (metadata & ~uint(type(uint64).max));
        if (positionBlock) (,,,,,cur) = cur.unpackPosition();
        else (,,cur) = cur.unpackBalance();
        return (uint32(cur) - base, uint32(cur >> 32) - base, cur >> 64);
    }
}
