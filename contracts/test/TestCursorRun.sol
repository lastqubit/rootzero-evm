// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {Blocks, Cursors} from "../Codec.sol";

/// @dev A direct count-only assembly reference for hint-scan comparisons.
library CursorRunCandidates {
    function composed(uint cur, bytes4 key) internal pure returns (uint total) {
        uint abs = uint32(cur);
        uint endAbs = uint32(cur >> 32);
        while (abs < endAbs) {
            uint head = uint(Blocks.read32(abs));
            if (bytes4(bytes32(head)) != key) break;
            unchecked {
                uint nextAbs = abs + 8 + uint32(head >> 192);
                if (nextAbs > endAbs) break;
                abs = nextAbs;
                ++total;
            }
        }
    }

    function fused(uint cur, bytes4 key) internal pure returns (uint total) {
        assembly ("memory-safe") {
            let abs := and(cur, 0xffffffff)
            let endAbs := and(shr(32, cur), 0xffffffff)
            let expected := shr(224, key)
            for {} lt(abs, endAbs) {} {
                let head := calldataload(abs)
                if iszero(eq(shr(224, head), expected)) { break }
                let nextAbs := add(add(abs, 8), and(shr(192, head), 0xffffffff))
                if gt(nextAbs, endAbs) { break }
                abs := nextAbs
                total := add(total, 1)
            }
        }
    }
}
abstract contract CursorRunHarness {
    function scan(uint cur, bytes4 key) internal pure virtual returns (uint total);
    function inspect(bytes calldata source, uint length, uint offset, uint metadata, bytes4 key)
        external pure returns (uint total)
    {
        require(length <= source.length);
        uint baseAbs = Cursors.base(source);
        return scan((baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max)), key);
    }
    function raw(uint cur, bytes4 key) external pure returns (uint total) {
        return scan(cur, key);
    }
    function measure(bytes calldata source, bytes4 key) external view returns (uint gasUsed, uint total) {
        uint cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        total = scan(cur, key);
        gasUsed = beforeGas - gasleft();
    }
}
contract CursorRunBaseline is CursorRunHarness {
    function scan(uint cur, bytes4 key) internal pure override returns (uint) {
        return LegacyBlocks.runCount(uint32(cur), uint32(cur >> 32), key);
    }
}
contract CursorRunFused is CursorRunHarness {
    function scan(uint cur, bytes4 key) internal pure override returns (uint) {
        return CursorRunCandidates.fused(cur, key);
    }
}
contract CursorRunCurrent is CursorRunHarness {
    function scan(uint cur, bytes4 key) internal pure override returns (uint) {
        return Blocks.runCount(cur, key);
    }
}

contract CursorRunComposed is CursorRunHarness {
    function scan(uint cur, bytes4 key) internal pure override returns (uint) {
        return CursorRunCandidates.composed(cur, key);
    }
}
