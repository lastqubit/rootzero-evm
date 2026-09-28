// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {RangeCursorBlocks} from "./RangeCursorBlocks.sol";
import {Blocks, Cursors, Keys} from "../Codec.sol";
import {OutOfBounds, INVALID_BLOCK, OUT_OF_BOUNDS} from "../utils/Errors.sol";
import {BALANCE_HEADER} from "../codec/Specs.sol";
import {FusedCursorBlocks} from "./FusedCursorBlocks.sol";

/// @dev Deliberately retain candidates for repeatable structure comparisons.
library CursorUnpackCandidates {
    function composed(uint cur, bytes4 key) internal pure returns (bytes32 a, bytes32 b, uint blockCur) {
        (blockCur, ) = Blocks.takeFixed(cur, (uint64(uint32(key)) << 32) | 64);
        uint start = uint32(blockCur);
        assembly ("memory-safe") {
            a := calldataload(add(start, 8))
            b := calldataload(add(start, 40))
        }
    }

    function fused(uint cur, bytes4 key) internal pure returns (bytes32 a, bytes32 b, uint blockCur) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            if iszero(eq(shr(192, calldataload(start)), or(shl(32, shr(224, key)), 64))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            let end := add(start, 72)
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
            a := calldataload(add(start, 8))
            b := calldataload(add(start, 40))
            blockCur := or(start, shl(32, end))
        }
    }

    function fixedEnd(uint cur, bytes4 key) private pure returns (uint end) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            if iszero(eq(shr(192, calldataload(start)), or(shl(32, shr(224, key)), 64))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            end := add(start, 72)
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
        }
    }

    function endOnly(uint cur, bytes4 key) internal pure returns (bytes32 a, bytes32 b, uint blockCur) {
        uint end = fixedEnd(cur, key);
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            a := calldataload(add(start, 8))
            b := calldataload(add(start, 40))
            blockCur := or(start, shl(32, end))
        }
    }

    function balance(uint cur) internal pure returns (bytes32 asset, uint amount, uint blockCur) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            if iszero(eq(shr(192, calldataload(start)), BALANCE_HEADER)) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            let end := add(start, 72)
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
            asset := calldataload(add(start, 8))
            amount := calldataload(add(start, 40))
            blockCur := or(start, shl(32, end))
        }
    }
}

abstract contract CursorUnpackHarness {
    function decode(uint cur, bytes4 key) internal pure virtual returns (bytes32 a, bytes32 b, uint blockCur);

    function inspect(bytes calldata source, uint length, uint offset, bytes4 key)
        external pure returns (bytes32 a, bytes32 b, uint blockCur, uint base)
    {
        require(length <= source.length);
        base = Cursors.base(source);
        uint cur = (base + offset) | ((base + length) << 32) | (uint(0xabcdef1234567890) << 64);
        (a, b, blockCur) = decode(cur, key);
    }

    function raw(uint cur, bytes4 key) external pure returns (bytes32, bytes32, uint) {
        return decode(cur, key);
    }

    function measure(bytes calldata source, bytes4 key) external view returns (uint gasUsed, uint checksum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 a, bytes32 b, uint blockCur) = decode(cur, key);
            unchecked { checksum += uint(a) + uint(b); }
            cur = (cur & ~uint(type(uint32).max)) | (blockCur >> 32);
        }
        gasUsed = beforeGas - gasleft();
    }

    function measureValues(bytes calldata source, bytes4 key) external view returns (uint gasUsed, uint checksum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 a, bytes32 b,) = decode(cur, key);
            unchecked { checksum += uint(a) + uint(b); cur += 72; }
        }
        gasUsed = beforeGas - gasleft();
    }
}

contract CursorUnpackBaseline is CursorUnpackHarness {
    function decode(uint cur, bytes4 key) internal pure override returns (bytes32 a, bytes32 b, uint blockCur) {
        uint start = uint32(cur);
        uint end;
        (a, b, end) = LegacyBlocks.unpack64(start, uint(uint32(key)) << 224);
        if (end > uint32(cur >> 32)) revert OutOfBounds();
        blockCur = start | (end << 32);
    }
}
contract CursorUnpackComposed is CursorUnpackHarness {
    function decode(uint cur, bytes4 key) internal pure override returns (bytes32, bytes32, uint) {
        return CursorUnpackCandidates.composed(cur, key);
    }
}
contract CursorUnpackFused is CursorUnpackHarness {
    function decode(uint cur, bytes4 key) internal pure override returns (bytes32, bytes32, uint) {
        return CursorUnpackCandidates.fused(cur, key);
    }
}
contract CursorUnpackEnd is CursorUnpackHarness {
    function decode(uint cur, bytes4 key) internal pure override returns (bytes32, bytes32, uint) {
        return CursorUnpackCandidates.endOnly(cur, key);
    }
}
contract CursorUnpackBalanceBaseline is CursorUnpackHarness {
    function decode(uint cur, bytes4) internal pure override returns (bytes32 a, bytes32 b, uint blockCur) {
        uint start = uint32(cur);
        uint amount;
        (a, amount) = LegacyBlocks.unpackBalance(start);
        uint end;
        unchecked { end = start + 72; }
        if (end > uint32(cur >> 32)) revert OutOfBounds();
        b = bytes32(amount);
        blockCur = start | (end << 32);
    }
}
contract CursorUnpackBalanceComposed is CursorUnpackHarness {
    function decode(uint cur, bytes4) internal pure override returns (bytes32, bytes32, uint) {
        return CursorUnpackCandidates.composed(cur, Keys.Balance);
    }
}
contract CursorUnpackBalanceFused is CursorUnpackHarness {
    function decode(uint cur, bytes4) internal pure override returns (bytes32, bytes32, uint) {
        return CursorUnpackCandidates.fused(cur, Keys.Balance);
    }
}
contract CursorUnpackBalanceDirect is CursorUnpackHarness {
    function decode(uint cur, bytes4) internal pure override returns (bytes32 a, bytes32 b, uint blockCur) {
        uint amount;
        (a, amount, blockCur) = CursorUnpackCandidates.balance(cur);
        b = bytes32(amount);
    }
}
contract CursorUnpackRangeReference is CursorUnpackHarness {
    function decode(uint cur, bytes4 key) internal pure override returns (bytes32, bytes32, uint) {
        return RangeCursorBlocks.unpack64(cur, key);
    }
}
contract CursorUnpackBalanceRangeReference is CursorUnpackHarness {
    function decode(uint cur, bytes4) internal pure override returns (bytes32 a, bytes32 b, uint blockCur) {
        uint amount;
        (a, amount, blockCur) = RangeCursorBlocks.unpackBalance(cur);
        b = bytes32(amount);
    }
}
contract CursorUnpackFusedReference is CursorUnpackHarness {
    function decode(uint cur, bytes4 key) internal pure override returns (bytes32, bytes32, uint) {
        return FusedCursorBlocks.unpack64(cur, key);
    }
}
contract CursorUnpackBalanceFusedReference is CursorUnpackHarness {
    function decode(uint cur, bytes4) internal pure override returns (bytes32 a, bytes32 b, uint blockCur) {
        uint amount;
        (a, amount, blockCur) = FusedCursorBlocks.unpackBalance(cur);
        b = bytes32(amount);
    }
}
