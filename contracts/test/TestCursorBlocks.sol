// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

// Import through the public barrel to cover the new export as well.
import {Blocks, Cursors} from "../Codec.sol";
import {OutOfBounds, InvalidBlock} from "../utils/Errors.sol";
import {CursorEntryCandidates} from "./CursorEntryCandidates.sol";
import {PreviousCursorBlocks} from "./PreviousCursorBlocks.sol";
import {FusedCursorBlocks} from "./FusedCursorBlocks.sol";

contract TestCursorBlocks {
    function inspect(
        bytes calldata source, uint length, uint offset, uint spec, uint amount, uint8 mode, bool packed
    ) external pure returns (uint result, uint base, uint stream) {
        require(length <= source.length);
        base = Cursors.base(source);
        // Preserve a complete execution-like metadata word, not just one flag.
        stream = (base + offset) | ((base + length) << 32) | (uint(0x3123456789abcdef01) << 64);
        result = select(stream, spec, amount, mode, packed);
        // Successful selection proves this update; no checked seek is needed.
        stream = (stream & ~uint(type(uint32).max)) | uint32(result >> 32);
    }

    function raw(uint cur, uint spec, uint amount, uint8 mode) external pure returns (uint) {
        return select(cur, spec, amount, mode, true);
    }

    function select(uint cur, uint spec, uint amount, uint8 mode, bool packed) internal pure virtual returns (uint result) {
        bytes4 key = bytes4(uint32(spec >> 224));
        if (packed) {
            if (mode == 0) { (uint selected, ) = Blocks.take(cur); return selected; }
            if (mode == 1) { (uint selected, ) = Blocks.take(cur, spec); return selected; }
            if (mode == 2) { (uint selected, ) = Blocks.take(cur, key); return selected; }
            if (mode == 3) { (uint selected, ) = Blocks.takeFixed(cur, uint64(spec >> 192)); return selected; }
            if (mode == 4) { (uint selected, ) = Blocks.unpack(cur, spec); return selected; }
            if (mode == 5) { (uint selected, ) = Blocks.unpack(cur, key); return selected; }
            if (mode == 6) { (, result, ) = Blocks.enter(cur, spec, amount); return result; }
            if (mode == 7) { (, result, ) = Blocks.enter(cur, key, amount); return result; }
            return Blocks.unpackExact(cur, spec);
        }
        uint start = uint32(cur);
        uint limit = uint32(cur >> 32);
        uint body;
        uint end;
        if (mode == 0) {
            (, uint len) = LegacyBlocks.peek(start, limit);
            end = start + 8 + len;
        } else if (mode == 3) {
            // LegacyBlocks.enterFixed is private; reproduce its exact-header check.
            uint64 header;
            assembly ("memory-safe") { header := shr(192, calldataload(start)) }
            if (header != uint64(spec >> 192)) revert InvalidBlock();
            end = start + 8 + uint32(spec >> 192);

        } else if (mode == 2 || mode == 5 || mode == 7) {
            (body, end) = LegacyBlocks.enter(start, key);
        } else if (mode == 8) {
            bytes calldata source;
            assembly ("memory-safe") { source.offset := start source.length := sub(limit, start) }
            body = LegacyBlocks.exact(source, spec);
            end = limit;
        } else {
            (body, end) = LegacyBlocks.enter(start, spec);
        }
        if (end > limit) revert OutOfBounds();
        if (mode >= 4) start = body;
        if (mode == 6 || mode == 7) {
            if (amount > end - start) revert InvalidBlock();
            start += amount;
        }
        result = start | (end << 32);
    }

    function nested(bytes calldata source, uint parentSpec, uint childSpec) external pure returns (uint parent, uint child) {
        (parent, ) = Blocks.unpack(Cursors.wrap(source), parentSpec);
        (child, ) = Blocks.take(parent, childSpec);
    }
}

contract TestCursorTakeExact is TestCursorBlocks {
    function enterExact(bytes calldata source, uint length, uint spec, uint amount) external pure returns (uint abs, uint payloadCur, uint base) {
        require(length <= source.length);
        base = Cursors.base(source);
        uint cur = base | ((base + length) << 32) | (uint(0xa5) << 64);
        (abs, payloadCur) = Blocks.enterExact(cur, spec, amount);
    }

    function select(uint cur, uint spec, uint amount, uint8 mode, bool packed) internal pure override returns (uint) {
        if (packed) return Blocks.takeExact(cur, spec);
        return super.select(cur, spec, amount, mode, packed);
    }
}

contract TestCursorFixedExact {
    function inspect(bytes calldata source, uint start, uint end, uint header, uint metadata, bool payload)
        external pure returns (uint selected, uint original)
    {
        require(start <= source.length && end <= source.length);
        uint base = Cursors.base(source);
        original = (base + start) | ((base + end) << 32) | (metadata & ~uint(type(uint64).max));
        selected = select(original, header, payload);
    }

    function select(uint cur, uint header, bool payload) public pure returns (uint) {
        return payload ? Blocks.unpackFixedExact(cur, header) : Blocks.takeFixedExact(cur, header);
    }
}

contract TestCursorEntryCandidates is TestCursorBlocks {
    function select(uint cur, uint spec, uint amount, uint8 mode, bool packed) internal pure override returns (uint) {
        if (packed) {
            if (mode == 3) return CursorEntryCandidates.fixedExpected(cur, uint64(spec >> 192));
            if (mode == 4) return CursorEntryCandidates.enter(cur, spec);
            if (mode == 5) return CursorEntryCandidates.enter(cur, bytes4(uint32(spec >> 224)));
            if (mode == 6) return CursorEntryCandidates.enterLen(cur, spec, amount);
            if (mode == 7) return CursorEntryCandidates.enterLen(cur, bytes4(uint32(spec >> 224)), amount);
        }
        return super.select(cur, spec, amount, mode, packed);
    }
}
contract TestFusedCursorBlocks is TestCursorBlocks {
    function select(uint cur, uint spec, uint amount, uint8 mode, bool packed) internal pure override returns (uint) {
        if (!packed) return super.select(cur, spec, amount, mode, false);
        bytes4 key = bytes4(uint32(spec >> 224));
        if (mode == 0) return FusedCursorBlocks.take(cur);
        if (mode == 1) return FusedCursorBlocks.take(cur, spec);
        if (mode == 2) return FusedCursorBlocks.take(cur, key);
        if (mode == 3) return FusedCursorBlocks.takeFixed(cur, uint64(spec >> 192));
        if (mode == 4) return FusedCursorBlocks.enter(cur, spec);
        if (mode == 5) return FusedCursorBlocks.enter(cur, key);
        if (mode == 6) return FusedCursorBlocks.enter(cur, spec, amount);
        if (mode == 7) return FusedCursorBlocks.enter(cur, key, amount);
        return FusedCursorBlocks.exact(cur, spec);
    }
}

/// @dev Identical consumers with distinct tuple/packed producer contracts.
abstract contract CursorBlocksTupleScan {
    function range(uint cur, uint spec) internal pure virtual returns (uint start, uint end);
    function measure(bytes calldata source, uint spec) external view returns (uint usedGas, uint checksum, uint finalCur) {
        uint cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (uint start, uint end) = range(cur, spec);
            unchecked { checksum += end - start; }
            cur = (cur & ~uint(type(uint32).max)) | end;
        }
        usedGas = beforeGas - gasleft();
        finalCur = cur;
    }
}

abstract contract CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure virtual returns (uint);
    function measure(bytes calldata source, uint spec) external view returns (uint usedGas, uint checksum, uint finalCur) {
        uint cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint selected = range(cur, spec);
            uint end = selected >> 32;
            unchecked { checksum += end - uint32(selected); }
            cur = (cur & ~uint(type(uint32).max)) | end;
        }
        usedGas = beforeGas - gasleft();
        finalCur = cur;
    }
}

/// @dev Current consuming API: assign the helper's returned source cursor directly.
abstract contract CursorBlocksAdvancingScan {
    function range(uint cur, uint spec) internal pure virtual returns (uint selected, uint nextCur);
    function measure(bytes calldata source, uint spec) external view returns (uint usedGas, uint checksum, uint finalCur) {
        uint cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint selected;
            (selected, cur) = range(cur, spec);
            unchecked { checksum += uint32(selected >> 32) - uint32(selected); }
        }
        usedGas = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorBlocksSpecBaseline is CursorBlocksTupleScan {
    function range(uint cur, uint spec) internal pure override returns (uint start, uint end) {
        start = uint32(cur);
        (, end) = LegacyBlocks.enter(start, spec);
        if (end > uint32(cur >> 32)) revert OutOfBounds();
    }
}
contract CursorBlocksSpecPacked is CursorBlocksAdvancingScan {
    function range(uint cur, uint spec) internal pure override returns (uint selected, uint nextCur) { return Blocks.take(cur, spec); }
}
contract CursorBlocksKeyBaseline is CursorBlocksTupleScan {
    function range(uint cur, uint spec) internal pure override returns (uint start, uint end) {
        start = uint32(cur);
        (, end) = LegacyBlocks.enter(start, bytes4(uint32(spec >> 224)));
        if (end > uint32(cur >> 32)) revert OutOfBounds();
    }
}
contract CursorBlocksKeyPacked is CursorBlocksAdvancingScan {
    function range(uint cur, uint spec) internal pure override returns (uint selected, uint nextCur) { return Blocks.take(cur, bytes4(uint32(spec >> 224))); }
}
contract CursorBlocksFixedBaseline is CursorBlocksTupleScan {
    function range(uint cur, uint spec) internal pure override returns (uint start, uint end) {
        start = uint32(cur);
        uint64 header;
        assembly ("memory-safe") { header := shr(192, calldataload(start)) }
        if (header != uint64(spec >> 192)) revert InvalidBlock();
        unchecked { end = start + 8 + uint32(spec >> 192); }
        if (end > uint32(cur >> 32)) revert OutOfBounds();
    }
}
contract CursorBlocksFixedPacked is CursorBlocksAdvancingScan {
    function range(uint cur, uint spec) internal pure override returns (uint selected, uint nextCur) { return Blocks.takeFixed(cur, spec >> 192); }
}
contract CursorBlocksPeekBaseline is CursorBlocksTupleScan {
    function range(uint cur, uint) internal pure override returns (uint start, uint end) {
        start = uint32(cur);
        (, uint len) = LegacyBlocks.peek(start, uint32(cur >> 32));
        unchecked { end = start + 8 + len; }
    }
}
contract CursorBlocksPeekPacked is CursorBlocksAdvancingScan {
    function range(uint cur, uint spec) internal pure override returns (uint selected, uint nextCur) { return Blocks.take(cur); }
}
contract CursorBlocksEnterBaseline is CursorBlocksTupleScan {
    function range(uint cur, uint spec) internal pure override returns (uint start, uint end) {
        (start, end) = LegacyBlocks.enter(uint32(cur), spec);
        if (end > uint32(cur >> 32)) revert OutOfBounds();
    }
}
contract CursorBlocksEnterPacked is CursorBlocksAdvancingScan {
    function range(uint cur, uint spec) internal pure override returns (uint selected, uint nextCur) { return Blocks.unpack(cur, spec); }
}
contract CursorBlocksPrefixBaseline is CursorBlocksTupleScan {
    function range(uint cur, uint spec) internal pure override returns (uint start, uint end) {
        (, start, end) = LegacyBlocks.enter(uint32(cur), spec, 16);
        if (end > uint32(cur >> 32)) revert OutOfBounds();
    }
}
contract CursorBlocksPrefixPacked is CursorBlocksAdvancingScan {
    function range(uint cur, uint spec) internal pure override returns (uint selected, uint nextCur) { (, selected, nextCur) = Blocks.enter(cur, spec, 16); }
}
contract CursorBlocksEnterFusedBaseline is CursorBlocksEnterBaseline {}
contract CursorBlocksFixedExpectedBaseline is CursorBlocksFixedBaseline {}
contract CursorBlocksFixedExpectedPacked is CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure override returns (uint) { return CursorEntryCandidates.fixedExpected(cur, uint64(spec >> 192)); }
}
contract CursorBlocksEnterFusedPacked is CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure override returns (uint) { return CursorEntryCandidates.enter(cur, spec); }
}
contract CursorBlocksPrefixFusedBaseline is CursorBlocksPrefixBaseline {}
contract CursorBlocksPrefixLenBaseline is CursorBlocksPrefixBaseline {}
contract CursorBlocksPrefixLenPacked is CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure override returns (uint) { return CursorEntryCandidates.enterLen(cur, spec, 16); }
}
contract CursorBlocksPrefixFusedPacked is CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure override returns (uint) { return CursorEntryCandidates.enter(cur, spec, 16); }
}
contract CursorBlocksEnterPreviousBaseline is CursorBlocksEnterBaseline {}
contract CursorBlocksEnterPreviousPacked is CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure override returns (uint) { return PreviousCursorBlocks.enter(cur, spec); }
}
contract CursorBlocksPrefixPreviousBaseline is CursorBlocksPrefixBaseline {}
contract CursorBlocksPrefixPreviousPacked is CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure override returns (uint) { return PreviousCursorBlocks.enter(cur, spec, 16); }
}
contract CursorBlocksSpecFusedReferenceBaseline is CursorBlocksSpecBaseline {}
contract CursorBlocksSpecFusedReferencePacked is CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure override returns (uint) { return FusedCursorBlocks.take(cur, spec); }
}
contract CursorBlocksKeyFusedReferenceBaseline is CursorBlocksKeyBaseline {}
contract CursorBlocksKeyFusedReferencePacked is CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure override returns (uint) { return FusedCursorBlocks.take(cur, bytes4(uint32(spec >> 224))); }
}
contract CursorBlocksFixedFusedReferenceBaseline is CursorBlocksFixedBaseline {}
contract CursorBlocksFixedFusedReferencePacked is CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure override returns (uint) { return FusedCursorBlocks.takeFixed(cur, uint64(spec >> 192)); }
}
contract CursorBlocksPeekFusedReferenceBaseline is CursorBlocksPeekBaseline {}
contract CursorBlocksPeekFusedReferencePacked is CursorBlocksPackedScan {
    function range(uint cur, uint) internal pure override returns (uint) { return FusedCursorBlocks.take(cur); }
}
contract CursorBlocksEnterFusedReferenceBaseline is CursorBlocksEnterBaseline {}
contract CursorBlocksEnterFusedReferencePacked is CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure override returns (uint) { return FusedCursorBlocks.enter(cur, spec); }
}
contract CursorBlocksPrefixFusedReferenceBaseline is CursorBlocksPrefixBaseline {}
contract CursorBlocksPrefixFusedReferencePacked is CursorBlocksPackedScan {
    function range(uint cur, uint spec) internal pure override returns (uint) { return FusedCursorBlocks.enter(cur, spec, 16); }
}

/// @dev Exercises the internal raw-read API from a consuming contract.
contract TestCursorRead32 {
    function readAt(bytes calldata source, uint offset) external pure returns (bytes32 value, bytes32 previous) {
        uint abs;
        assembly ("memory-safe") { abs := add(source.offset, offset) }
        return (Blocks.read32(abs), LegacyBlocks.read32(abs));
    }

    function readAbsolute(uint abs) external pure returns (bytes32) {
        return Blocks.read32(abs);
    }
}
