// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder} from "../codec/Encoder.sol";
import {EagerAbsoluteEncoder} from "./EagerAbsoluteEncoder.sol";
import {LazyRelativeEncoder} from "./LazyRelativeEncoder.sol";

abstract contract EagerEncoderHarness {
    function init(uint capacity) internal pure virtual returns (uint, bytes memory);
    function balance(uint cur, bytes memory dst, bytes32 asset, uint amount) internal pure virtual returns (uint, bytes memory);
    function context(uint cur, bytes memory dst, bytes32 account, bytes memory state, bytes memory input, uint stateCur, uint inputCur, uint mode) internal pure virtual returns (uint, bytes memory);
    function finish(uint cur, bytes memory dst) internal pure virtual returns (bytes memory);
    function reserve(uint cur, bytes memory dst, uint size) internal pure virtual returns (uint, bytes memory, uint);

    function inspect(uint capacity, uint count) external pure returns (uint metadata, bytes memory output, bytes32 padding) {
        assembly ("memory-safe") {
            let p := mload(0x40)
            for { let end := add(p, 8192) } lt(p, end) { p := add(p, 32) } { mstore(p, not(0)) }
        }
        (uint cur, bytes memory dst) = init(capacity);
        cur |= uint(0xabcdef) << 128;
        for (uint j; j < count; ++j) {
            uint abs;
            (cur, dst, abs) = reserve(cur, dst, 9);
            abs = Encoder.writeHeader(abs, bytes4(0x01020304), 1);
            assembly ("memory-safe") { mstore8(abs, and(j, 255)) }
            bytes memory guard = new bytes(32);
            assembly ("memory-safe") { mstore(add(guard, 32), 0xfeed) }
            (cur, dst, abs) = reserve(cur, dst, 8);
            Encoder.writeHeader(abs, bytes4(0x05060708), 0);
            bytes32 saved;
            assembly ("memory-safe") { saved := mload(add(guard, 32)) }
            assert(saved == bytes32(uint(0xfeed)));
        }
        metadata = cur >> 128;
        output = finish(cur, dst);
        assembly ("memory-safe") { padding := mload(add(add(output, 32), mload(output))) }
    }

    function overflow(uint capacity, uint size) external pure {
        (uint cur, bytes memory dst) = init(capacity);
        reserve(cur, dst, size);
    }

    function balances(bytes32 asset, uint amount, uint count, uint capacity) external view returns (uint used, bytes memory output) {
        uint beforeGas = gasleft();
        (uint cur, bytes memory dst) = init(capacity);
        for (uint j; j < count; ++j) (cur, dst) = balance(cur, dst, asset, amount);
        output = finish(cur, dst);
        used = beforeGas - gasleft();
    }
    function contexts(bytes32 account, bytes calldata state, bytes calldata input, uint count, uint capacity, uint mode) external view returns (uint used, bytes memory output) {
        bytes memory stateMemory = state;
        bytes memory inputMemory = input;
        uint stateCur;
        uint inputCur;
        assembly ("memory-safe") {
            stateCur := or(state.offset, shl(32, add(state.offset, state.length)))
            inputCur := or(input.offset, shl(32, add(input.offset, input.length)))
        }
        uint beforeGas = gasleft();
        (uint cur, bytes memory dst) = init(capacity);
        for (uint j; j < count; ++j) (cur, dst) = context(cur, dst, account, stateMemory, inputMemory, stateCur, inputCur, mode);
        output = finish(cur, dst);
        used = beforeGas - gasleft();
    }
}

contract TestLazyRelativeEncoder is EagerEncoderHarness {
    function reserve(uint cur, bytes memory dst, uint size) internal pure override returns (uint, bytes memory, uint) { return LazyRelativeEncoder.reserve(cur, dst, size); }
    function init(uint capacity) internal pure override returns (uint cur, bytes memory dst) { cur = LazyRelativeEncoder.init(capacity); }
    function balance(uint cur, bytes memory dst, bytes32 asset, uint amount) internal pure override returns (uint, bytes memory) { return LazyRelativeEncoder.writeBalance(cur, dst, asset, amount); }
    function finish(uint cur, bytes memory dst) internal pure override returns (bytes memory) { return LazyRelativeEncoder.finish(cur, dst); }
    function context(uint cur, bytes memory dst, bytes32 account, bytes memory state, bytes memory input, uint stateCur, uint inputCur, uint mode) internal pure override returns (uint, bytes memory) {
        if (mode == 0) return LazyRelativeEncoder.writeContext(cur, dst, account, state, input);
        if (mode == 1) return LazyRelativeEncoder.writeContext(cur, dst, account, stateCur, inputCur);
        if (mode == 2) return LazyRelativeEncoder.writeContextWrap(cur, dst, account, state, input);
        return LazyRelativeEncoder.writeContextWrap(cur, dst, account, stateCur, inputCur);
    }
}

contract TestEagerRelativeEncoder is EagerEncoderHarness {
    function reserve(uint cur, bytes memory dst, uint size) internal pure override returns (uint nextCur, bytes memory value, uint abs) { (value, abs, nextCur) = Encoder.reserve(cur, dst, size); }
    function init(uint capacity) internal pure override returns (uint cur, bytes memory dst) { (dst, cur) = Encoder.init(capacity); }
    function balance(uint cur, bytes memory dst, bytes32 asset, uint amount) internal pure override returns (uint nextCur, bytes memory value) { (value, nextCur) = Encoder.writeBalance(cur, dst, asset, amount); }
    function finish(uint cur, bytes memory dst) internal pure override returns (bytes memory) { return Encoder.finish(cur, dst); }
    function context(uint cur, bytes memory dst, bytes32 account, bytes memory state, bytes memory input, uint stateCur, uint inputCur, uint mode) internal pure override returns (uint nextCur, bytes memory value) {
        if (mode == 0) (value, nextCur) = Encoder.writeContext(cur, dst, account, state, input);
        else if (mode == 1) (value, nextCur) = Encoder.writeContext(cur, dst, account, stateCur, inputCur);
        else if (mode == 2) (value, nextCur) = Encoder.writeContextWrap(cur, dst, account, state, input);
        else (value, nextCur) = Encoder.writeContextWrap(cur, dst, account, stateCur, inputCur);
    }
}

contract TestEagerAbsoluteEncoder is EagerEncoderHarness {
    function reserve(uint cur, bytes memory dst, uint size) internal pure override returns (uint, bytes memory, uint) { return EagerAbsoluteEncoder.reserve(cur, dst, size); }
    function init(uint capacity) internal pure override returns (uint cur, bytes memory dst) { (cur, dst) = EagerAbsoluteEncoder.init(capacity); }
    function balance(uint cur, bytes memory dst, bytes32 asset, uint amount) internal pure override returns (uint, bytes memory) { return EagerAbsoluteEncoder.writeBalance(cur, dst, asset, amount); }
    function finish(uint cur, bytes memory dst) internal pure override returns (bytes memory) { return EagerAbsoluteEncoder.finish(cur, dst); }
    function context(uint cur, bytes memory dst, bytes32 account, bytes memory state, bytes memory input, uint stateCur, uint inputCur, uint mode) internal pure override returns (uint, bytes memory) {
        if (mode == 0) return EagerAbsoluteEncoder.writeContext(cur, dst, account, state, input);
        if (mode == 1) return EagerAbsoluteEncoder.writeContext(cur, dst, account, stateCur, inputCur);
        if (mode == 2) return EagerAbsoluteEncoder.writeContextWrap(cur, dst, account, state, input);
        return EagerAbsoluteEncoder.writeContextWrap(cur, dst, account, stateCur, inputCur);
    }
}
