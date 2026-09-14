// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";
import {Keys} from "../codec/Keys.sol";
import {Sizes, Specs} from "../codec/Specs.sol";

/// @dev Frozen leaf and fixed-header implementations for gas/error comparisons.
library PreviousLeafFixed {
    error InvalidBlock();
    function unpackList(uint abs) internal pure returns (bytes calldata value, uint end) {
        uint head;
        uint len;
        assembly ("memory-safe") {
            head := calldataload(abs)
            len := and(shr(192, head), 0xffffffff)
            value.offset := add(abs, 0x08)
            value.length := len
        }
        if (uint32(head >> 224) != uint32(Keys.List)) revert InvalidBlock();
        end = abs + Sizes.Header + len;
    }

    function unpackBytes(uint abs) internal pure returns (bytes calldata value, uint end) {
        uint head;
        uint len;
        assembly ("memory-safe") {
            head := calldataload(abs)
            len := and(shr(192, head), 0xffffffff)
            value.offset := add(abs, 0x08)
            value.length := len
        }
        if (uint32(head >> 224) != uint32(Keys.Bytes)) revert InvalidBlock();
        end = abs + Sizes.Header + len;
    }

    function unpackString(uint abs) internal pure returns (bytes calldata value, uint end) {
        uint head;
        uint len;
        assembly ("memory-safe") {
            head := calldataload(abs)
            len := and(shr(192, head), 0xffffffff)
            value.offset := add(abs, 0x08)
            value.length := len
        }
        if (uint32(head >> 224) != uint32(Keys.String)) revert InvalidBlock();
        end = abs + Sizes.Header + len;
    }

    function expectFixed(uint abs, bytes4 key, uint size) private pure returns (uint body, uint end) {
        if (Blocks.header(abs, key) != size) revert InvalidBlock();
        unchecked {
            body = abs + Sizes.Header;
            end = body + size;
        }
    }

    function expectEmpty(uint abs, bytes4 key) internal pure returns (uint end) {
        if (Blocks.header(abs, key) != 0) revert InvalidBlock();
        return abs + Sizes.Header;
    }

    function unpack32(uint abs, uint spec) internal pure returns (bytes32 a, uint end) {
        (abs, end) = expectFixed(abs, Specs.key(spec), 32);
        a = Blocks.read32(abs);
    }

    function unpack64(uint abs, uint spec) internal pure returns (bytes32 a, bytes32 b, uint end) {
        (abs, end) = expectFixed(abs, Specs.key(spec), 64);
        assembly ("memory-safe") {
            a := calldataload(abs)
            b := calldataload(add(abs, 0x20))
        }
    }

    function unpack96(
        uint abs,
        uint spec
    ) internal pure returns (bytes32 a, bytes32 b, bytes32 c, uint end) {
        (abs, end) = expectFixed(abs, Specs.key(spec), 96);
        assembly ("memory-safe") {
            a := calldataload(abs)
            b := calldataload(add(abs, 0x20))
            c := calldataload(add(abs, 0x40))
        }
    }

    function unpack128(
        uint abs,
        uint spec
    ) internal pure returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, uint end) {
        (abs, end) = expectFixed(abs, Specs.key(spec), 128);
        assembly ("memory-safe") {
            a := calldataload(abs)
            b := calldataload(add(abs, 0x20))
            c := calldataload(add(abs, 0x40))
            d := calldataload(add(abs, 0x60))
        }
    }

    function unpack160(
        uint abs,
        uint spec
    ) internal pure returns (bytes32 a, bytes32 b, bytes32 c, bytes32 d, bytes32 e, uint end) {
        (abs, end) = expectFixed(abs, Specs.key(spec), 160);
        assembly ("memory-safe") {
            a := calldataload(abs)
            b := calldataload(add(abs, 0x20))
            c := calldataload(add(abs, 0x40))
            d := calldataload(add(abs, 0x60))
            e := calldataload(add(abs, 0x80))
        }
    }
}

contract TestLeafFixed {
    /// @dev Return slice bounds without copying potentially four GiB of payload.
    function leafBounds(bool optimized, uint kind, bytes calldata data)
        external pure returns(uint offset, uint length, uint end) {
        uint abs; assembly ("memory-safe") { abs := data.offset }
        bytes calldata value;
        if (kind == 0) {
            if (optimized) (value, end) = Blocks.unpackList(abs);
            else (value, end) = PreviousLeafFixed.unpackList(abs);
        } else if (kind == 1) {
            if (optimized) (value, end) = Blocks.unpackBytes(abs);
            else (value, end) = PreviousLeafFixed.unpackBytes(abs);
        } else {
            if (optimized) (value, end) = Blocks.unpackString(abs);
            else (value, end) = PreviousLeafFixed.unpackString(abs);
        }
        assembly ("memory-safe") { offset := sub(value.offset, abs) length := value.length }
        end -= abs;
    }

    function unpackList(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        bytes calldata value; uint end;
        uint initial = gasleft();
        if (optimized) (value, end) = Blocks.unpackList(abs);
        else (value, end) = PreviousLeafFixed.unpackList(abs);
        usedGas = initial - gasleft();
        output = abi.encode(value, end);
    }
    function unpackBytes(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        bytes calldata value; uint end;
        uint initial = gasleft();
        if (optimized) (value, end) = Blocks.unpackBytes(abs);
        else (value, end) = PreviousLeafFixed.unpackBytes(abs);
        usedGas = initial - gasleft();
        output = abi.encode(value, end);
    }
    function unpackString(bool optimized, bytes calldata data, uint start, bool absolute)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        bytes calldata value; uint end;
        uint initial = gasleft();
        if (optimized) (value, end) = Blocks.unpackString(abs);
        else (value, end) = PreviousLeafFixed.unpackString(abs);
        usedGas = initial - gasleft();
        output = abi.encode(value, end);
    }
    function enterEmpty(bool optimized, bytes calldata data, uint start, bool absolute, bytes4 key)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        uint end;
        uint initial = gasleft();
        if (optimized) end = Blocks.enterEmpty(abs, key);
        else end = PreviousLeafFixed.expectEmpty(abs, key);
        usedGas = initial - gasleft();
        output = abi.encode(end);
    }
    function unpack32(bool optimized, bytes calldata data, uint start, bool absolute, uint spec)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        return measure32(optimized, abs, spec);
    }
    function measure32(bool optimized, uint abs, uint spec)
        private view returns(uint usedGas, bytes memory output) {
        bytes32 a; uint end;
        uint initial = gasleft();
        if (optimized) (a, end) = Blocks.unpack32(abs, spec);
        else (a, end) = PreviousLeafFixed.unpack32(abs, spec);
        usedGas = initial - gasleft();
        output = abi.encode(a, end);
    }
    function unpack64(bool optimized, bytes calldata data, uint start, bool absolute, uint spec)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        return measure64(optimized, abs, spec);
    }
    function measure64(bool optimized, uint abs, uint spec)
        private view returns(uint usedGas, bytes memory output) {
        bytes32 a; bytes32 b; uint end;
        uint initial = gasleft();
        if (optimized) (a, b, end) = Blocks.unpack64(abs, spec);
        else (a, b, end) = PreviousLeafFixed.unpack64(abs, spec);
        usedGas = initial - gasleft();
        output = abi.encode(a, b, end);
    }
    function unpack96(bool optimized, bytes calldata data, uint start, bool absolute, uint spec)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        return measure96(optimized, abs, spec);
    }
    function measure96(bool optimized, uint abs, uint spec)
        private view returns(uint usedGas, bytes memory output) {
        bytes32 a; bytes32 b; bytes32 c; uint end;
        uint initial = gasleft();
        if (optimized) (a, b, c, end) = Blocks.unpack96(abs, spec);
        else (a, b, c, end) = PreviousLeafFixed.unpack96(abs, spec);
        usedGas = initial - gasleft();
        output = abi.encode(a, b, c, end);
    }
    function unpack128(bool optimized, bytes calldata data, uint start, bool absolute, uint spec)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        return measure128(optimized, abs, spec);
    }
    function measure128(bool optimized, uint abs, uint spec)
        private view returns(uint usedGas, bytes memory output) {
        bytes32 a; bytes32 b; bytes32 c; bytes32 d; uint end;
        uint initial = gasleft();
        if (optimized) (a, b, c, d, end) = Blocks.unpack128(abs, spec);
        else (a, b, c, d, end) = PreviousLeafFixed.unpack128(abs, spec);
        usedGas = initial - gasleft();
        output = abi.encode(a, b, c, d, end);
    }
    function unpack160(bool optimized, bytes calldata data, uint start, bool absolute, uint spec)
        external view returns(uint usedGas, bytes memory output) {
        uint base; assembly ("memory-safe") { base := data.offset }
        uint abs = absolute ? start : base + start;
        return measure160(optimized, abs, spec);
    }
    function measure160(bool optimized, uint abs, uint spec)
        private view returns(uint usedGas, bytes memory output) {
        bytes32 a; bytes32 b; bytes32 c; bytes32 d; bytes32 e; uint end;
        uint initial = gasleft();
        if (optimized) (a, b, c, d, e, end) = Blocks.unpack160(abs, spec);
        else (a, b, c, d, e, end) = PreviousLeafFixed.unpack160(abs, spec);
        usedGas = initial - gasleft();
        output = abi.encode(a, b, c, d, e, end);
    }
}
