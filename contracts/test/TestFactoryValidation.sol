// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {Keys} from "../codec/Keys.sol";
import {Sizes} from "../codec/Specs.sol";
import {max32} from "../utils/Utils.sol";

/// @dev Frozen generic writers and factories, with the current allocator so the
/// comparison isolates length-validation changes rather than allocation changes.
library PreviousFactoryValidation {
    function allocate(uint len) private pure returns (bytes memory value) {
        assembly ("memory-safe") {
            value := mload(0x40)
            let padded := and(add(len, 31), not(31))
            let tail := add(add(value, 0x20), padded)
            mstore(0x40, add(tail, 0x20))
            mstore(value, len)
            mstore(add(add(value, 0x20), len), 0)
        }
    }

    function write(bytes memory dst, uint i, bytes4 key, bytes memory payload) internal pure {
        uint len = max32(payload.length);
        uint head = (uint(uint32(key)) << 224) | (len << 192);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, head)
            mcopy(add(p, 0x08), add(payload, 0x20), len)
        }
    }

    function copy(bytes memory dst, uint i, bytes4 key, bytes calldata payload) internal pure {
        uint len = max32(payload.length);
        uint head = (uint(uint32(key)) << 224) | (len << 192);
        assembly ("memory-safe") {
            let p := add(add(dst, 0x20), i)
            mstore(p, head)
            calldatacopy(add(p, 0x08), payload.offset, len)
        }
    }

    function create(bytes4 key, bytes memory payload) internal pure returns (bytes memory value) {
        uint len = max32(payload.length);
        value = allocate(Sizes.Header + len);
        write(value, 0, key, payload);
    }

    function createCopy(bytes4 key, bytes calldata payload) internal pure returns (bytes memory value) {
        uint len = max32(payload.length);
        value = allocate(Sizes.Header + len);
        copy(value, 0, key, payload);
    }

    function copyList(bytes memory dst, uint i, bytes calldata value) internal pure { copy(dst, i, Keys.List, value); }
    function copyBytes(bytes memory dst, uint i, bytes calldata value) internal pure { copy(dst, i, Keys.Bytes, value); }
    function copyString(bytes memory dst, uint i, string calldata value) internal pure { copy(dst, i, Keys.String, bytes(value)); }

    function createListCopy(bytes calldata value) internal pure returns (bytes memory blockdata) {
        uint len = max32(value.length);
        blockdata = allocate(Sizes.Header + len);
        copyList(blockdata, 0, value);
    }

    function createBytesCopy(bytes calldata value) internal pure returns (bytes memory blockdata) {
        uint len = max32(value.length);
        blockdata = allocate(Sizes.Header + len);
        copyBytes(blockdata, 0, value);
    }

    function createStringCopy(string calldata value) internal pure returns (bytes memory blockdata) {
        uint len = max32(bytes(value).length);
        blockdata = allocate(Sizes.Header + len);
        copyString(blockdata, 0, value);
    }
}

contract TestFactoryValidation {
    // 0 memory factory, 1 calldata factory, 2/3/4 LIST/BYTES/STRING factories,
    // 5 standalone memory writer, 6 standalone calldata writer.
    function measure(bool optimized, uint kind, bytes calldata input)
        external view returns (uint usedGas, bytes memory output)
    {
        bytes memory memoryInput = input;
        if (kind >= 5) {
            output = new bytes(input.length + 40);
            assembly ("memory-safe") { mstore(output, add(input.length, 8)) }
        }
        uint initial = gasleft();
        if (kind == 0) output = optimized ? Blocks.create(Keys.Bytes, memoryInput) : PreviousFactoryValidation.create(Keys.Bytes, memoryInput);
        else if (kind == 1) output = optimized ? Blocks.createCopy(Keys.Bytes, input) : PreviousFactoryValidation.createCopy(Keys.Bytes, input);
        else if (kind == 2) output = optimized ? Blocks.createListCopy(input) : PreviousFactoryValidation.createListCopy(input);
        else if (kind == 3) output = optimized ? Blocks.createBytesCopy(input) : PreviousFactoryValidation.createBytesCopy(input);
        else if (kind == 4) output = optimized ? Blocks.createStringCopy(string(input)) : PreviousFactoryValidation.createStringCopy(string(input));
        else if (kind == 5) {
            if (optimized) Blocks.write(output, 0, Keys.Bytes, memoryInput);
            else PreviousFactoryValidation.write(output, 0, Keys.Bytes, memoryInput);
        } else {
            if (optimized) Blocks.copy(output, 0, Keys.Bytes, input);
            else PreviousFactoryValidation.copy(output, 0, Keys.Bytes, input);
        }
        usedGas = initial - gasleft();
    }

    /// @dev Forge oversized lengths without allocating GiB of memory. Every entry
    /// must reject before copying or accessing the imaginary payload.
    function oversized(bool optimized, uint kind, bytes calldata input, uint length) external pure {
        bytes memory dst = new bytes(64);
        bytes memory memoryInput;
        assembly ("memory-safe") {
            input.length := length
            memoryInput := mload(0x40)
            mstore(memoryInput, length)
            mstore(0x40, add(memoryInput, 32))
        }
        if (kind == 0) {
            if (optimized) Blocks.create(Keys.Bytes, memoryInput);
            else PreviousFactoryValidation.create(Keys.Bytes, memoryInput);
        } else if (kind == 1) {
            if (optimized) Blocks.createCopy(Keys.Bytes, input);
            else PreviousFactoryValidation.createCopy(Keys.Bytes, input);
        } else if (kind == 2) {
            if (optimized) Blocks.createListCopy(input);
            else PreviousFactoryValidation.createListCopy(input);
        } else if (kind == 3) {
            if (optimized) Blocks.createBytesCopy(input);
            else PreviousFactoryValidation.createBytesCopy(input);
        } else if (kind == 4) {
            if (optimized) Blocks.createStringCopy(string(input));
            else PreviousFactoryValidation.createStringCopy(string(input));
        } else if (kind == 5) {
            if (optimized) Blocks.write(dst, 0, Keys.Bytes, memoryInput);
            else PreviousFactoryValidation.write(dst, 0, Keys.Bytes, memoryInput);
        } else {
            if (optimized) Blocks.copy(dst, 0, Keys.Bytes, input);
            else PreviousFactoryValidation.copy(dst, 0, Keys.Bytes, input);
        }
    }
}
