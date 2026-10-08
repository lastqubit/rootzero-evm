// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Encoder} from "../codec/Encoder.sol";

abstract contract EncoderBufferHarness {
    function init(uint capacity) internal pure virtual returns (uint, bytes memory);
    function reserve(uint cur, bytes memory dst, uint size, uint scratch) internal pure virtual returns (uint, bytes memory, uint);
    function append(uint cur, bytes memory dst, bytes32 account, bytes memory state, bytes memory input, uint stateCur, uint inputCur, uint mode) internal pure virtual returns (uint, bytes memory);
    function finish(uint cur, bytes memory dst) internal pure virtual returns (bytes memory);
    function balance(uint cur, bytes memory dst, bytes32 asset, uint amount) internal pure virtual returns (uint, bytes memory);

    function balances(bytes32 asset, uint amount, uint count, uint capacity, bool warm) external view returns (uint used, bytes memory output) {
        uint beforeGas = gasleft();
        (uint cur, bytes memory dst) = init(capacity);
        if (warm) {
            (cur, dst,) = reserve(cur, dst, 0, 0);
            assembly ("memory-safe") { mstore(add(dst, mload(dst)), 0) }
        }
        if (warm) beforeGas = gasleft();
        for (uint j; j < count; ++j) (cur, dst) = balance(cur, dst, asset, amount);
        output = finish(cur, dst);
        used = beforeGas - gasleft();
    }

    function measure(bytes32 account, bytes calldata state, bytes calldata input, uint count, uint capacity, uint mode, bool warm)
        external view returns (uint used, uint allocated, uint cur, bytes memory output)
    {
        bytes memory stateMemory = state;
        bytes memory inputMemory = input;
        uint stateCur;
        uint inputCur;
        assembly ("memory-safe") {
            stateCur := or(state.offset, shl(32, add(state.offset, state.length)))
            inputCur := or(input.offset, shl(32, add(input.offset, input.length)))
        }
        uint beforeMemory;
        assembly ("memory-safe") { beforeMemory := mload(0x40) }
        uint beforeGas = gasleft();
        bytes memory dst;
        (cur, dst) = init(capacity);
        cur |= uint(0xabcdef) << 128;
        if (warm) {
            (cur, dst,) = reserve(cur, dst, 0, 0);
            // Equalize memory expansion: the new allocator leaves capacity dirty.
            assembly ("memory-safe") { mstore(add(dst, mload(dst)), 0) }
        }
        if (warm) {
            assembly ("memory-safe") { beforeMemory := mload(0x40) }
            beforeGas = gasleft();
        }
        for (uint j; j < count; ++j) {
            (cur, dst) = append(cur, dst, account, stateMemory, inputMemory, stateCur, inputCur, mode);
        }
        output = finish(cur, dst);
        used = beforeGas - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), beforeMemory) }
    }
}

contract TestEncoderBuffer is EncoderBufferHarness {
    function init(uint capacity) internal pure override returns (uint nextCur, bytes memory value) {
        (value, nextCur) = Encoder.init(capacity);
    }
    function balance(uint cur, bytes memory dst, bytes32 asset, uint amount) internal pure override returns (uint nextCur, bytes memory value) {
        (value, nextCur) = Encoder.writeBalance(cur, dst, asset, amount);
    }
    function reserve(uint cur, bytes memory dst, uint size, uint) internal pure override returns (uint nextCur, bytes memory value, uint abs) {
        (value, abs, nextCur) = Encoder.reserve(cur, dst, size);
    }
    function finish(uint cur, bytes memory dst) internal pure override returns (bytes memory) {
        return Encoder.finish(cur, dst);
    }
    function append(uint cur, bytes memory dst, bytes32 account, bytes memory state, bytes memory input, uint stateCur, uint inputCur, uint mode) internal pure override returns (uint nextCur, bytes memory value) {
        if (mode == 0) (value, nextCur) = Encoder.writeBalance(cur, dst, account, 123);
        else if (mode == 1) (value, nextCur) = Encoder.writeContext(cur, dst, account, state, input);
        else if (mode == 2) (value, nextCur) = Encoder.writeContext(cur, dst, account, stateCur, inputCur);
        else if (mode == 3) (value, nextCur) = Encoder.writeContextWrap(cur, dst, account, state, input);
        else (value, nextCur) = Encoder.writeContextWrap(cur, dst, account, stateCur, inputCur);
    }

    function overflow(uint capacity, uint size) external pure {
        (uint cur, bytes memory dst) = init(capacity);
        Encoder.reserve(cur, dst, size);
    }

    function dirty(uint capacity, uint count) external pure returns (bytes memory output, bytes32 padding, bytes32 guard) {
        // Model dirty free memory left by temporary work, without retaining it.
        assembly ("memory-safe") {
            let p := mload(0x40)
            for { let end := add(p, 8192) } lt(p, end) { p := add(p, 32) } { mstore(p, not(0)) }
        }
        (uint cur, bytes memory dst) = init(capacity);
        for (uint j; j < count; ++j) {
            uint abs;
            (dst, abs, cur) = Encoder.reserve(cur, dst, 9);
            abs = Encoder.writeHeader(abs, bytes4(0x01020304), 1);
            assembly ("memory-safe") { mstore8(abs, and(j, 255)) }
            // A retained allocation must survive later scratch writes and growth.
            bytes memory sentinel = new bytes(32);
            assembly ("memory-safe") { mstore(add(sentinel, 32), 0xfeed) }
            (dst, abs, cur) = Encoder.reserve(cur, dst, 8);
            Encoder.writeHeader(abs, bytes4(0x05060708), 0);
            assembly ("memory-safe") { guard := mload(add(sentinel, 32)) }
            assert(guard == bytes32(uint(0xfeed)));
        }
        output = Encoder.finish(cur, dst);
        assembly ("memory-safe") { padding := mload(add(add(output, 32), mload(output))) }
    }
}
