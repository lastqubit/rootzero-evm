// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";

contract TestCursorGenericUnpack {
    function prefix(bytes calldata source, uint offset, uint length, uint spec, uint amount, bool keyed)
        external pure returns (uint abs, uint payloadCur, uint original, uint nextCur)
    {
        require(length <= source.length && offset <= source.length);
        uint base;
        assembly ("memory-safe") { base := source.offset }
        original = (base + offset) | ((base + length) << 32) | (uint(0xa5) << 64);
        if (keyed) (abs, payloadCur, nextCur) = Blocks.enter(original, bytes4(uint32(spec >> 224)), amount);
        else (abs, payloadCur, nextCur) = Blocks.enter(original, spec, amount);
    }

    function inspect(bytes calldata source, uint offset, uint length, uint metadata, uint spec, bool keyed)
        external pure returns (uint payloadCur, uint nextCur, uint original)
    {
        require(length <= source.length && offset <= source.length);
        uint abs;
        assembly ("memory-safe") { abs := source.offset }
        original = (abs + offset) | ((abs + length) << 32) | (metadata & ~uint(type(uint64).max));
        return keyed ? unpackKey(original, bytes4(uint32(spec >> 224))) : unpackSpec(original, spec);
    }
    function unpackKey(uint cur, bytes4 key) private pure returns (uint payloadCur, uint nextCur, uint original) {
        (payloadCur, nextCur) = Blocks.unpack(cur, key);
        original = cur;
    }
    function unpackSpec(uint cur, uint spec) private pure returns (uint payloadCur, uint nextCur, uint original) {
        (payloadCur, nextCur) = Blocks.unpack(cur, spec);
        original = cur;
    }
    function scan(bytes calldata source, uint spec, bool keyed) external pure returns (uint count, uint total) {
        uint cur;
        assembly ("memory-safe") { cur := or(source.offset, shl(32, add(source.offset, source.length))) }
        while (uint32(cur) < uint32(cur >> 32)) {
            uint payloadCur;
            if (keyed) (payloadCur, cur) = Blocks.unpack(cur, bytes4(uint32(spec >> 224)));
            else (payloadCur, cur) = Blocks.unpack(cur, spec);
            total += uint32(payloadCur >> 32) - uint32(payloadCur);
            ++count;
        }
    }
}
