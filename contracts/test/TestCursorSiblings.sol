// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {RangeCursorBlocks} from "./RangeCursorBlocks.sol";
import {Blocks, Cursors, Keys} from "../Codec.sol";
import {Specs} from "../codec/Specs.sol";
import {INVALID_BLOCK, OUT_OF_BOUNDS} from "../utils/Errors.sol";

/// @dev Retained alternatives for measuring cursor handoff and redundant checks.
library CursorSiblingsCandidates {
    function composed(uint cur, bytes4 key, uint prefix) internal pure returns (uint first, uint last) {
        (, uint body, ) = Blocks.enter(cur, key, prefix);
        (first, ) = Blocks.unpack(body, key == Keys.Context ? Keys.State : Keys.Input);
        uint rest = (body & ~uint(type(uint32).max)) | (first >> 32);
        last = Blocks.unpackExact(rest, key == Keys.Context ? Specs.Input : Specs.Bytes);
    }

    function checked(uint cur, bytes4 key, uint prefix) internal pure returns (uint first, uint last) {
        return fused(cur, key, prefix, true);
    }

    function fused(uint cur, bytes4 key, uint prefix, bool checkFirst) internal pure returns (uint first, uint last) {
        uint firstKey = uint32(key == Keys.Context ? Keys.State : Keys.Input);
        uint lastKey = uint32(key == Keys.Context ? Keys.Input : Keys.Bytes);
        assembly ("memory-safe") {
            let start := and(cur, 0xffffffff)
            let header := calldataload(start)
            if iszero(eq(shr(224, header), shr(224, key))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            let end := add(add(start, 8), and(shr(192, header), 0xffffffff))
            if gt(end, and(shr(32, cur), 0xffffffff)) {
                mstore(0, OUT_OF_BOUNDS)
                revert(28, 4)
            }
            let child := add(add(start, 8), prefix)
            header := calldataload(child)
            if iszero(eq(shr(224, header), firstKey)) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            let body := add(child, 8)
            let next := add(body, and(shr(192, header), 0xffffffff))
            if checkFirst {
                if gt(next, end) {
                    mstore(0, INVALID_BLOCK)
                    revert(28, 4)
                }
            }
            let finalBody := add(next, 8)
            if or(lt(end, finalBody), iszero(eq(shr(192, calldataload(next)), or(shl(32, lastKey), sub(end, finalBody))))) {
                mstore(0, INVALID_BLOCK)
                revert(28, 4)
            }
            first := or(body, shl(32, next))
            last := or(finalBody, shl(32, end))
        }
    }
}

abstract contract CursorSiblingsHarness {
    function decode(uint cur) internal pure virtual returns (bytes32 account, uint first, uint last);
    function decodeData(uint cur) internal pure virtual returns (bytes32 account, bytes calldata first, bytes calldata last, uint end) {
        uint a; uint b;
        (account, a, b) = decode(cur);
        first = Cursors.toBytes(a); last = Cursors.toBytes(b); end = uint32(b >> 32);
    }
    function inspect(bytes calldata source, uint length, uint offset) external pure
        returns (bytes32 account, uint first, uint last, uint base, bytes memory a, bytes memory b)
    {
        require(length <= source.length);
        base = Cursors.base(source);
        (account, first, last) = decode((base + offset) | ((base + length) << 32) | (uint(0xfedcba) << 64));
        a = Cursors.toBytes(first); b = Cursors.toBytes(last);
    }
    function values(bytes calldata source, uint length, uint offset) external pure returns (bytes32 account) {
        require(length <= source.length);
        uint base = Cursors.base(source);
        (account,,) = decode((base + offset) | ((base + length) << 32));
    }
    function measureCursor(bytes calldata source) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 account, uint first, uint last) = decode(cur);
            unchecked { sum += uint(account) + uint32(first >> 32) - uint32(first) + uint32(last >> 32) - uint32(last); }
            cur = (cur & ~uint(type(uint32).max)) | (last >> 32);
        }
        gasUsed = beforeGas - gasleft();
    }
    function measureData(bytes calldata source) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 account, bytes calldata first, bytes calldata last, uint end) = decodeData(cur);
            unchecked { sum += uint(account) + uint(keccak256(first)) + uint(keccak256(last)); }
            cur = (cur & ~uint(type(uint32).max)) | end;
        }
        gasUsed = beforeGas - gasleft();
    }
}

contract CursorRelayBaseline is CursorSiblingsHarness {
    function decodeData(uint cur) internal pure override returns (bytes32 account, bytes calldata first, bytes calldata last, uint end) {
        (first, last, end) = LegacyBlocks.unpackRelay(uint32(cur));
        assembly ("memory-safe") {
            if gt(end, and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
        }
    }
    function decode(uint cur) internal pure override returns (bytes32 account, uint first, uint last) {
        bytes calldata a; bytes calldata b; uint end;
        (account, a, b, end) = decodeData(cur);
        assembly ("memory-safe") {
            first := or(a.offset, shl(32, add(a.offset, a.length)))
            last := or(b.offset, shl(32, end))
        }
    }
}

contract CursorRelayComposed is CursorSiblingsHarness {
    function decode(uint cur) internal pure override returns (bytes32 account, uint first, uint last) {
        (first, last) = CursorSiblingsCandidates.composed(cur, Keys.Relay, 0);
    }
}

contract CursorRelayChecked is CursorSiblingsHarness {
    function decode(uint cur) internal pure override returns (bytes32 account, uint first, uint last) {
        (first, last) = CursorSiblingsCandidates.checked(cur, Keys.Relay, 0);
    }
}

contract CursorRelayFused is CursorSiblingsHarness {
    function decode(uint cur) internal pure override returns (bytes32 account, uint first, uint last) {
        (first, last) = CursorSiblingsCandidates.fused(cur, Keys.Relay, 0, false);
    }
}

contract CursorRelayRangeReference is CursorSiblingsHarness {
    function decode(uint cur) internal pure override returns (bytes32 account, uint first, uint last) {
        (first, last) = RangeCursorBlocks.unpackRelay(cur);
    }
}

contract CursorContextBaseline is CursorSiblingsHarness {
    function decodeData(uint cur) internal pure override returns (bytes32 account, bytes calldata first, bytes calldata last, uint end) {
        (account, first, last, end) = LegacyBlocks.unpackContext(uint32(cur));
        assembly ("memory-safe") {
            if gt(end, and(shr(32, cur), 0xffffffff)) { mstore(0, OUT_OF_BOUNDS) revert(28, 4) }
        }
    }
    function decode(uint cur) internal pure override returns (bytes32 account, uint first, uint last) {
        bytes calldata a; bytes calldata b; uint end;
        (account, a, b, end) = decodeData(cur);
        assembly ("memory-safe") {
            first := or(a.offset, shl(32, add(a.offset, a.length)))
            last := or(b.offset, shl(32, end))
        }
    }
}

contract CursorContextComposed is CursorSiblingsHarness {
    function decode(uint cur) internal pure override returns (bytes32 account, uint first, uint last) {
        (first, last) = CursorSiblingsCandidates.composed(cur, Keys.Context, 32);
        assembly ("memory-safe") { account := calldataload(add(and(cur, 0xffffffff), 8)) }
    }
}

contract CursorContextChecked is CursorSiblingsHarness {
    function decode(uint cur) internal pure override returns (bytes32 account, uint first, uint last) {
        (first, last) = CursorSiblingsCandidates.checked(cur, Keys.Context, 32);
        assembly ("memory-safe") { account := calldataload(add(and(cur, 0xffffffff), 8)) }
    }
}

contract CursorContextFused is CursorSiblingsHarness {
    function decode(uint cur) internal pure override returns (bytes32 account, uint first, uint last) {
        (first, last) = CursorSiblingsCandidates.fused(cur, Keys.Context, 32, false);
        assembly ("memory-safe") { account := calldataload(add(and(cur, 0xffffffff), 8)) }
    }
}

contract CursorContextRangeReference is CursorSiblingsHarness {
    function decode(uint cur) internal pure override returns (bytes32 account, uint first, uint last) {
        return RangeCursorBlocks.unpackContext(cur);
    }
}
