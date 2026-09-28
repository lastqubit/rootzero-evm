// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder} from "../codec/Encoder.sol";
import {PreviousEncoderOrder} from "./PreviousEncoderOrder.sol";

// Identical consumers apart from library return order; preparation is outside measurement.
contract EncoderOrderPrevious {
    function measure(bytes32 account, bytes calldata state, bytes calldata input, uint count, uint capacity, uint mode)
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
        (cur, dst) = PreviousEncoderOrder.init(capacity);
        cur |= uint(0xabcdef) << 128;
        for (uint j; j < count; ++j) {
            if (mode == 0) (cur, dst) = PreviousEncoderOrder.writeBalance(cur, dst, account, 123);
            else if (mode == 1) (cur, dst) = PreviousEncoderOrder.writeContext(cur, dst, account, stateMemory, inputMemory);
            else if (mode == 2) (cur, dst) = PreviousEncoderOrder.writeContext(cur, dst, account, stateCur, inputCur);
            else if (mode == 3) (cur, dst) = PreviousEncoderOrder.writeContextWrap(cur, dst, account, stateMemory, inputMemory);
            else (cur, dst) = PreviousEncoderOrder.writeContextWrap(cur, dst, account, stateCur, inputCur);
        }
        output = PreviousEncoderOrder.finish(cur, dst);
        used = beforeGas - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), beforeMemory) }
    }
}
contract EncoderOrderCurrent {
    function measure(bytes32 account, bytes calldata state, bytes calldata input, uint count, uint capacity, uint mode)
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
        (dst, cur) = Encoder.init(capacity);
        cur |= uint(0xabcdef) << 128;
        for (uint j; j < count; ++j) {
            if (mode == 0) (dst, cur) = Encoder.writeBalance(cur, dst, account, 123);
            else if (mode == 1) (dst, cur) = Encoder.writeContext(cur, dst, account, stateMemory, inputMemory);
            else if (mode == 2) (dst, cur) = Encoder.writeContext(cur, dst, account, stateCur, inputCur);
            else if (mode == 3) (dst, cur) = Encoder.writeContextWrap(cur, dst, account, stateMemory, inputMemory);
            else (dst, cur) = Encoder.writeContextWrap(cur, dst, account, stateCur, inputCur);
        }
        output = Encoder.finish(cur, dst);
        used = beforeGas - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), beforeMemory) }
    }
}
