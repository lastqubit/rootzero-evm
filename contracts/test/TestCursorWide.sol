// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {RangeCursorBlocks} from "./RangeCursorBlocks.sol";
import {Blocks, Cursors} from "../Codec.sol";
import {INVALID_BLOCK, OUT_OF_BOUNDS} from "../utils/Errors.sol";

abstract contract CursorWideHarness {
    function decode(uint cur, bytes4 key) internal pure virtual returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e, uint blockCur);
    function inspect(bytes calldata source, uint length, uint offset, bytes4 key) external pure
        returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e, uint blockCur, uint base)
    {
        require(length <= source.length);
        base = Cursors.base(source);
        (a,b,c,d,e,blockCur) = decode((base + offset) | ((base + length) << 32) | (uint(0xfedcba) << 64), key);
    }
    function measure(bytes calldata source, bytes4 key) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e, uint selected) = decode(cur, key);
            unchecked { sum += uint(a) + uint(b) + uint(c) + uint(d) + uint(e); }
            cur = (cur & ~uint(type(uint32).max)) | (selected >> 32);
        }
        gasUsed = beforeGas - gasleft();
    }
    function measureValues(bytes calldata source, bytes4 key) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e,) = decode(cur, key);
            unchecked { sum += uint(a) + uint(b) + uint(c) + uint(d) + uint(e); cur += 168; }
        }
        gasUsed = beforeGas - gasleft();
    }
}
contract CursorWideBaseline is CursorWideHarness {
    function decode(uint cur, bytes4 key) internal pure override returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e, uint blockCur) {
        uint end;
        (a,b,c,d,e,end) = LegacyBlocks.unpack160(uint32(cur), uint(uint32(key)) << 224);
        assembly ("memory-safe") {
            if gt(end, and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            blockCur := or(and(cur, 0xffffffff), shl(32, end))
        }
    }
}
contract CursorWideComposed is CursorWideHarness {
    function decode(uint cur, bytes4 key) internal pure override returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e, uint blockCur) {
        (blockCur, ) = Blocks.takeFixed(cur, (uint64(uint32(key)) << 32) | 160);
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            a := calldataload(add(start, 8))
            b := calldataload(add(start, 40))
            c := calldataload(add(start, 72))
            d := calldataload(add(start, 104))
            e := calldataload(add(start, 136))
        }
    }
}
contract CursorWideFused is CursorWideHarness {
    function decode(uint cur, bytes4 key) internal pure override returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e, uint blockCur) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            if iszero(eq(shr(192, calldataload(start)), or(shl(32, shr(224, key)), 160))) {
                mstore(0, INVALID_BLOCK) revert(28, 4)
            }
            let end := add(start, 168)
            if gt(end, and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
            blockCur := or(start, shl(32, end))
        }
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            a := calldataload(add(start, 8))
            b := calldataload(add(start, 40))
            c := calldataload(add(start, 72))
            d := calldataload(add(start, 104))
            e := calldataload(add(start, 136))
        }
    }
}
contract CursorWideRangeReference is CursorWideHarness {
    function decode(uint cur, bytes4 key) internal pure override returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e, uint blockCur) {
        return RangeCursorBlocks.unpack160(cur, key);
    }
}
