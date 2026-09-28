// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {EncoderBufferHarness} from "./TestEncoderBuffer.sol";
import {AbsoluteEncoderBuffer} from "./AbsoluteEncoderBuffer.sol";
import {LazyRelativeEncoder} from "./LazyRelativeEncoder.sol";
import {Encoder} from "../codec/Encoder.sol";

contract TestAbsoluteEncoderBuffer is EncoderBufferHarness {
    function init(uint capacity) internal pure override returns (uint cur, bytes memory dst) {
        cur = LazyRelativeEncoder.init(capacity);
    }
    function balance(uint cur, bytes memory dst, bytes32 asset, uint amount) internal pure override returns (uint, bytes memory) {
        return AbsoluteEncoderBuffer.writeBalance(cur, dst, asset, amount);
    }
    function reserve(uint cur, bytes memory dst, uint size, uint) internal pure override returns (uint, bytes memory, uint) {
        return AbsoluteEncoderBuffer.reserve(cur, dst, size);
    }
    function finish(uint cur, bytes memory dst) internal pure override returns (bytes memory) {
        return AbsoluteEncoderBuffer.finish(cur, dst);
    }
    function append(uint cur, bytes memory dst, bytes32 account, bytes memory state, bytes memory input, uint stateCur, uint inputCur, uint mode) internal pure override returns (uint, bytes memory) {
        if (mode == 0) return AbsoluteEncoderBuffer.writeBalance(cur, dst, account, 123);
        if (mode == 1) return AbsoluteEncoderBuffer.writeContext(cur, dst, account, state, input);
        if (mode == 2) return AbsoluteEncoderBuffer.writeContext(cur, dst, account, stateCur, inputCur);
        if (mode == 3) return AbsoluteEncoderBuffer.writeContextWrap(cur, dst, account, state, input);
        return AbsoluteEncoderBuffer.writeContextWrap(cur, dst, account, stateCur, inputCur);
    }

    function inspect(uint capacity, uint count) external pure returns (uint cur, uint base, bytes memory output, bytes32 padding) {
        cur = LazyRelativeEncoder.init(capacity) | (uint(0xabcdef) << 128);
        bytes memory dst;
        assembly ("memory-safe") {
            let p := mload(0x40)
            for { let end := add(p, 8192) } lt(p, end) { p := add(p, 32) } { mstore(p, not(0)) }
        }
        for (uint j; j < count; ++j) {
            uint abs;
            (cur, dst, abs) = AbsoluteEncoderBuffer.reserve(cur, dst, 8);
            assert(abs == uint32(cur) - 8);
            Encoder.writeHeader(abs, bytes4(0x01020304), 0);
            bytes memory guard = new bytes(32);
            assembly ("memory-safe") { mstore(add(guard, 32), 0xfeed) }
            (cur, dst, abs) = AbsoluteEncoderBuffer.reserve(cur, dst, 9);
            abs = Encoder.writeHeader(abs, bytes4(0x05060708), 1);
            assembly ("memory-safe") { mstore8(abs, and(j, 255)) }
            assert(uint32(cur) >= Encoder.pos(dst, 0));
            assert(uint32(cur) <= uint32(cur >> 32));
            bytes32 saved;
            assembly ("memory-safe") { saved := mload(add(guard, 32)) }
            assert(saved == bytes32(uint(0xfeed)));
        }
        base = Encoder.pos(dst, 0);
        output = AbsoluteEncoderBuffer.finish(cur, dst);
        assembly ("memory-safe") { padding := mload(add(add(output, 32), mload(output))) }
    }

    function overflow(uint size) external pure {
        bytes memory dst;
        AbsoluteEncoderBuffer.reserve(0, dst, size);
    }
}
