// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";

abstract contract CursorRawReaderHarness {
    function read1(uint abs) public pure virtual returns (bytes1 value);
    function read2(uint abs) public pure virtual returns (bytes2 value);
    function read4(uint abs) public pure virtual returns (bytes4 value);
    function read8(uint abs) public pure virtual returns (bytes8 value);
    function read16(uint abs) public pure virtual returns (bytes16 value);
    function read32(uint abs) public pure virtual returns (bytes32 value);

    function readAt(bytes calldata source, uint offset) external pure
        returns (bytes1, bytes2, bytes4, bytes8, bytes16, bytes32)
    {
        uint abs;
        assembly ("memory-safe") { abs := add(source.offset, offset) }
        return (read1(abs), read2(abs), read4(abs), read8(abs), read16(abs), read32(abs));
    }
}

contract CursorRawReadersCurrent is CursorRawReaderHarness {
    function read1(uint abs) public pure override returns (bytes1 value) {
        return Blocks.read1(abs);
    }
    function read2(uint abs) public pure override returns (bytes2 value) {
        return Blocks.read2(abs);
    }
    function read4(uint abs) public pure override returns (bytes4 value) {
        return Blocks.read4(abs);
    }
    function read8(uint abs) public pure override returns (bytes8 value) {
        return Blocks.read8(abs);
    }
    function read16(uint abs) public pure override returns (bytes16 value) {
        return Blocks.read16(abs);
    }
    function read32(uint abs) public pure override returns (bytes32 value) {
        return Blocks.read32(abs);
    }
}

contract CursorRawReadersDirect is CursorRawReaderHarness {
    function read1(uint abs) public pure override returns (bytes1 value) {
        assembly ("memory-safe") { value := calldataload(abs) }
    }
    function read2(uint abs) public pure override returns (bytes2 value) {
        assembly ("memory-safe") { value := calldataload(abs) }
    }
    function read4(uint abs) public pure override returns (bytes4 value) {
        assembly ("memory-safe") { value := calldataload(abs) }
    }
    function read8(uint abs) public pure override returns (bytes8 value) {
        assembly ("memory-safe") { value := calldataload(abs) }
    }
    function read16(uint abs) public pure override returns (bytes16 value) {
        assembly ("memory-safe") { value := calldataload(abs) }
    }
    function read32(uint abs) public pure override returns (bytes32 value) {
        assembly ("memory-safe") { value := calldataload(abs) }
    }
}
