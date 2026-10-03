// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {RangeCursorBlocks} from "./RangeCursorBlocks.sol";
import {Blocks, Cursors, Keys} from "../Codec.sol";
import {Specs} from "../codec/Specs.sol";
import {INPUT_KEY, STEP_KEY} from "../codec/Keys.sol";
import {INVALID_BLOCK, OUT_OF_BOUNDS} from "../utils/Errors.sol";

library CursorDynamicCandidates {
    function composed(uint cur) internal pure returns (uint a, uint b, uint input) {
        (, uint payloadCur, ) = Blocks.enter(cur, Keys.Step, 64);
        input = Blocks.unpackExact(payloadCur, Specs.Input);
        (a, b) = words(cur);
    }

    function expected(uint cur) internal pure returns (uint a, uint b, uint input) {
        // The outer range is bounded once. Exact tail validation also proves
        // that the two fixed words and the child header fit the parent.
        (uint outer, ) = Blocks.take(cur, Keys.Step);
        unchecked { input = tail(uint(uint32(outer)) + 72, uint32(outer >> 32)); }
        (a, b) = words(cur);
    }

    function tail(uint start, uint end) private pure returns (uint input) {
        assembly ("memory-safe") {
            let body := add(start, 8)
            let len := sub(end, body)
            if or(gt(len, 0xffffffff), iszero(eq(shr(192, calldataload(start)), or(shl(32, INPUT_KEY), len)))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            input := or(body, shl(32, end))
        }
    }

    function words(uint cur) private pure returns (uint a, uint b) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            a := calldataload(add(start, 8))
            b := calldataload(add(start, 40))
        }
    }

    function fused(uint cur) internal pure returns (uint a, uint b, uint input) {
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            let head := calldataload(start)
            if iszero(eq(shr(224, head), STEP_KEY)) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            let end := add(add(start, 8), and(shr(192, head), 0xffffffff))
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
            let body := add(start, 80)
            let len := sub(end, body)
            if or(gt(len, 0xffffffff), iszero(eq(shr(192, calldataload(add(start, 72))), or(shl(32, INPUT_KEY), len)))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            a := calldataload(add(start, 8))
            b := calldataload(add(start, 40))
            input := or(body, shl(32, end))
        }
    }
}

abstract contract CursorDynamicHarness {
    function decode(uint cur) internal pure virtual returns (uint a, uint b, uint input);

    function decodeData(uint cur) internal pure virtual returns (uint a, uint b, bytes calldata data, uint end) {
        uint input;
        (a, b, input) = decode(cur);
        data = Cursors.toBytes(input);
        end = uint32(input >> 32);
    }

    function inspect(bytes calldata source, uint length, uint offset)
        external pure returns (uint a, uint b, uint input, uint base, bytes memory data)
    {
        require(length <= source.length);
        base = Cursors.base(source);
        uint cur = (base + offset) | ((base + length) << 32) | (uint(0xabcdef1234567890) << 64);
        (a, b, input) = decode(cur);
        data = Cursors.toBytes(input);
    }

    function values(bytes calldata source, uint length, uint offset) external pure returns (uint a, uint b) {
        require(length <= source.length);
        uint base = Cursors.base(source);
        (a, b,) = decode((base + offset) | ((base + length) << 32));
    }

    function measureCursor(bytes calldata source) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (uint a, uint b, uint input) = decode(cur);
            unchecked { sum += a + b + uint32(input >> 32) - uint32(input); }
            cur = (cur & ~uint(type(uint32).max)) | (input >> 32);
        }
        gasUsed = beforeGas - gasleft();
    }

    function measureData(bytes calldata source) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (uint a, uint b, bytes calldata data, uint end) = decodeData(cur);
            unchecked { sum += a + b + data.length + uint(keccak256(data)); }
            cur = (cur & ~uint(type(uint32).max)) | end;
        }
        gasUsed = beforeGas - gasleft();
    }
}

contract CursorDynamicBaseline is CursorDynamicHarness {
    function decodeData(uint cur) internal pure override returns (uint a, uint b, bytes calldata data, uint end) {
        (a, b, data, end) = LegacyBlocks.unpackStep(uint32(cur));
        assembly ("memory-safe") {
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
        }
    }
    function decode(uint cur) internal pure override returns (uint a, uint b, uint input) {
        bytes calldata data;
        uint end;
        (a, b, data, end) = decodeData(cur);
        assembly ("memory-safe") { input := or(data.offset, shl(32, end)) }
    }
}

contract CursorDynamicComposed is CursorDynamicHarness {
    function decode(uint cur) internal pure override returns (uint, uint, uint) {
        return CursorDynamicCandidates.composed(cur);
    }
}

contract CursorDynamicExpected is CursorDynamicHarness {
    function decode(uint cur) internal pure override returns (uint, uint, uint) {
        return CursorDynamicCandidates.expected(cur);
    }
}

contract CursorDynamicFused is CursorDynamicHarness {
    function decode(uint cur) internal pure override returns (uint, uint, uint) {
        return CursorDynamicCandidates.fused(cur);
    }
}

contract CursorDynamicRangeReference is CursorDynamicHarness {
    function decode(uint cur) internal pure override returns (uint, uint, uint) {
        return RangeCursorBlocks.unpackStep(cur);
    }
}
