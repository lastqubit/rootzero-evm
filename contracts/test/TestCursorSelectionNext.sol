// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";

contract TestCursorSelectionNext {
    function fixedPayload(bytes calldata source, uint offset, uint length, uint metadata, uint header, uint amount, bool prefix)
        external pure returns (uint abs, uint payloadCur, uint nextCur, uint original)
    {
        require(offset <= source.length && length <= source.length);
        uint base;
        assembly ("memory-safe") { base := source.offset }
        original = (base + offset) | ((base + length) << 32) | (metadata & ~uint(type(uint64).max));
        if (prefix) (abs, payloadCur, nextCur) = Blocks.enterFixed(original, header, amount);
        else (payloadCur, nextCur) = Blocks.unpackFixed(original, header);
    }
    function select(uint cur, uint spec, uint mode) private pure returns (uint blockCur, uint nextCur) {
        if (mode == 0) return Blocks.take(cur);
        if (mode == 1) return Blocks.take(cur, bytes4(uint32(spec >> 224)));
        if (mode == 2) return Blocks.take(cur, spec);
        return Blocks.takeFixed(cur, spec >> 192);
    }
    function inspect(bytes calldata source, uint offset, uint length, uint metadata, uint spec, uint mode)
        external pure returns (uint blockCur, uint nextCur, uint original)
    {
        require(offset <= source.length && length <= source.length);
        uint abs;
        assembly ("memory-safe") { abs := source.offset }
        original = (abs + offset) | ((abs + length) << 32) | (metadata & ~uint(type(uint64).max));
        (blockCur, nextCur) = select(original, spec, mode);
    }
    function scan(bytes calldata source, uint spec, uint mode, uint amount)
        external pure returns (uint count, uint total)
    {
        uint cur;
        assembly ("memory-safe") { cur := or(source.offset, shl(32, add(source.offset, source.length))) }
        while (uint32(cur) < uint32(cur >> 32)) {
            uint range;
            if (mode < 4) (range, cur) = select(cur, spec, mode);
            else if (mode == 4) (, range, cur) = Blocks.enter(cur, spec, amount);
            else if (mode == 5) (, range, cur) = Blocks.enter(cur, bytes4(uint32(spec >> 224)), amount);
            else if (mode == 6) (range, cur) = Blocks.unpackFixed(cur, spec >> 192);
            else (, range, cur) = Blocks.enterFixed(cur, spec >> 192, amount);
            ++count;
            total += uint32(range >> 32) - uint32(range);
        }
    }
}
