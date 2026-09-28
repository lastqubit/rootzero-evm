// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../Codec.sol";

abstract contract CursorCompareHarness {
    function valueFlags(uint abs, uint value) internal pure virtual returns (uint);
    function atFlags(uint abs, uint otherAbs) internal pure virtual returns (uint);

    function compareValue(bytes calldata source, uint offset, uint value) external pure returns (uint result) {
        uint abs;
        assembly ("memory-safe") { abs := add(source.offset, offset) }
        return valueFlags(abs, value);
    }
    function compareAt(bytes calldata source, uint offset, uint otherOffset) external pure returns (uint result) {
        uint abs; uint otherAbs;
        assembly ("memory-safe") { abs := add(source.offset, offset) otherAbs := add(source.offset, otherOffset) }
        return atFlags(abs, otherAbs);
    }
    function compareAbsolute(uint abs, uint otherAbs, uint value) external pure returns (uint byValue, uint byPosition) {
        return (valueFlags(abs, value), atFlags(abs, otherAbs));
    }
    function flags(bool eq_, bool ne_, bool lt_, bool le_, bool gt_, bool ge_) internal pure returns (uint result) {
        assembly ("memory-safe") {
            result := or(or(or(eq_, shl(1, ne_)), or(shl(2, lt_), shl(3, le_))), or(shl(4, gt_), shl(5, ge_)))
        }
    }
    function measureValue(bytes calldata source, uint value) external view returns (uint used, uint sum) {
        require(source.length % 32 == 0);
        uint abs; uint end;
        assembly ("memory-safe") { abs := source.offset end := add(abs, source.length) }
        uint beforeGas = gasleft();
        while (abs < end) {
            uint mask = valueFlags(abs, value);
            unchecked { sum += mask; abs += 32; }
        }
        used = beforeGas - gasleft();
    }
    function measureAt(bytes calldata source) external view returns (uint used, uint sum) {
        require(source.length >= 32 && source.length % 32 == 0);
        uint abs; uint otherAbs; uint end;
        assembly ("memory-safe") { otherAbs := source.offset abs := add(otherAbs, 32) end := add(otherAbs, source.length) }
        uint beforeGas = gasleft();
        while (abs < end) {
            uint mask = atFlags(abs, otherAbs);
            unchecked { sum += mask; abs += 32; }
        }
        used = beforeGas - gasleft();
    }
}
contract CursorCompareHelpers is CursorCompareHarness {
    function valueFlags(uint abs, uint value) internal pure override returns (uint) {
        return flags(Blocks.equal32(abs, bytes32(value)), !Blocks.equal32(abs, bytes32(value)),
            Blocks.lt32(abs, value), Blocks.le32(abs, value), Blocks.gt32(abs, value), Blocks.ge32(abs, value));
    }
    function atFlags(uint abs, uint otherAbs) internal pure override returns (uint) {
        return flags(Blocks.equalAt32(abs, otherAbs), !Blocks.equalAt32(abs, otherAbs),
            Blocks.ltAt32(abs, otherAbs), Blocks.leAt32(abs, otherAbs), Blocks.gtAt32(abs, otherAbs), Blocks.geAt32(abs, otherAbs));
    }
}
contract CursorCompareReads is CursorCompareHarness {
    function valueFlags(uint abs, uint value) internal pure override returns (uint) {
        uint a = uint(Blocks.read32(abs));
        return flags(a == value, a != value, a < value, a <= value, a > value, a >= value);
    }
    function atFlags(uint abs, uint otherAbs) internal pure override returns (uint) {
        uint a = uint(Blocks.read32(abs));
        uint b = uint(Blocks.read32(otherAbs));
        return flags(a == b, a != b, a < b, a <= b, a > b, a >= b);
    }
}
