// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";

contract TestCursorList {
    function unpack(uint cur) internal pure virtual returns (uint, uint) {
        return Blocks.unpackList(cur);
    }

    function inspect(bytes calldata source, uint offset, uint length, uint metadata)
        external pure returns (uint itemsCur, uint nextCur, uint original)
    {
        require(length <= source.length && offset <= source.length);
        uint abs;
        assembly ("memory-safe") { abs := source.offset }
        original = (abs + offset) | ((abs + length) << 32) | (metadata & ~uint(type(uint64).max));
        (itemsCur, nextCur) = unpack(original);
    }

    function scan(bytes calldata source) external pure returns (uint count, uint bytesTotal) {
        uint cur;
        assembly ("memory-safe") { cur := or(source.offset, shl(32, add(source.offset, source.length))) }
        while (uint32(cur) < uint32(cur >> 32)) {
            uint itemsCur;
            (itemsCur, cur) = unpack(cur);
            bytesTotal += uint32(itemsCur >> 32) - uint32(itemsCur);
            ++count;
        }
    }
}

contract TestCursorBytes is TestCursorList {
    function unpack(uint cur) internal pure override returns (uint, uint) {
        return Blocks.unpackBytes(cur);
    }
}

contract TestCursorString is TestCursorList {
    function unpack(uint cur) internal pure override returns (uint, uint) {
        return Blocks.unpackString(cur);
    }
}
