// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Decoders} from "../codec/Decoders.sol";
import {Cur} from "../utils/Cursors.sol";
import {PreviousDecoders} from "./PreviousDecoders.sol";
contract TestDecoderOptimization {
    struct Config { uint start; uint end; uint flags; uint parameter; uint repetitions; }
    struct Result { uint usedGas; uint state; bytes data; }
    function measure(bool optimized, uint mode, bytes calldata input, Config calldata cfg)
        external view returns(Result memory result) {
        Cur memory cur;
        uint base; assembly ("memory-safe") { base := input.offset }
        cur.state = (base + cfg.start) | ((base + cfg.end) << 32) | (cfg.flags << 64);
        uint initial = gasleft();
        for (uint j; j < cfg.repetitions; j++) result.data = step(optimized, mode, cur, cfg.parameter);
        result.usedGas = initial - gasleft();
        result.state = cur.state;
    }
    function step(bool optimized, uint mode, Cur memory cur, uint parameter) private pure returns(bytes memory data) {
        if (mode == 0) {
            bytes calldata v0;
            if (optimized) v0 = Decoders.unpackBytes(cur);
            else v0 = PreviousDecoders.unpackBytes(cur);
            data = abi.encode(v0);
        }
        else if (mode == 1) {
            uint v0; uint v1; bytes calldata v2;
            if (optimized) (v0, v1, v2) = Decoders.unpackStep(cur);
            else (v0, v1, v2) = PreviousDecoders.unpackStep(cur);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 2) {
            uint v0; uint v1;
            if (optimized) (v0, v1) = Decoders.consume(cur, parameter);
            else (v0, v1) = PreviousDecoders.consume(cur, parameter);
            data = abi.encode(v0, v1);
        }
        else if (mode == 3) {
            uint v0; uint v1;
            if (optimized) (v0, v1) = Decoders.consume(cur, bytes4(uint32(parameter)));
            else (v0, v1) = PreviousDecoders.consume(cur, bytes4(uint32(parameter)));
            data = abi.encode(v0, v1);
        }
        else if (mode == 4) {
            bytes calldata v0;
            if (optimized) v0 = Decoders.unpackRaw(cur, parameter);
            else v0 = PreviousDecoders.unpackRaw(cur, parameter);
            data = abi.encode(v0);
        }
        else if (mode == 5) {
            string memory v0;
            if (optimized) v0 = Decoders.unpackString(cur);
            else v0 = PreviousDecoders.unpackString(cur);
            data = abi.encode(v0);
        }
        else if (mode == 6) {
            bytes32 v0; bytes calldata v1; bytes calldata v2;
            if (optimized) (v0, v1, v2) = Decoders.unpackContext(cur);
            else (v0, v1, v2) = PreviousDecoders.unpackContext(cur);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 7) {
            bytes calldata v0; bytes calldata v1;
            if (optimized) (v0, v1) = Decoders.unpackRelay(cur);
            else (v0, v1) = PreviousDecoders.unpackRelay(cur);
            data = abi.encode(v0, v1);
        }
        else if (mode == 8) {
            bytes32 v0; string memory v1;
            if (optimized) (v0, v1) = Decoders.unpackLabel(cur);
            else (v0, v1) = PreviousDecoders.unpackLabel(cur);
            data = abi.encode(v0, v1);
        }
        else if (mode == 9) {
            uint v0; string memory v1;
            if (optimized) (v0, v1) = Decoders.unpackSchema(cur);
            else (v0, v1) = PreviousDecoders.unpackSchema(cur);
            data = abi.encode(v0, v1);
        }
        else if (mode == 10) {
            uint v0; uint v1; bytes32 v2; bytes calldata v3;
            if (optimized) (v0, v1, v2, v3) = Decoders.unpackRecover(cur);
            else (v0, v1, v2, v3) = PreviousDecoders.unpackRecover(cur);
            data = abi.encode(v0, v1, v2, v3);
        }
        else if (mode == 11) {
            uint v0; uint v1; bytes calldata v2;
            if (optimized) (v0, v1, v2) = Decoders.unpackCall(cur);
            else (v0, v1, v2) = PreviousDecoders.unpackCall(cur);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 12) {
            uint v0; uint v1; bytes calldata v2;
            if (optimized) (v0, v1, v2) = Decoders.unpackDispatch(cur);
            else (v0, v1, v2) = PreviousDecoders.unpackDispatch(cur);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 13) {
            uint v0; bytes calldata v1;
            if (optimized) (v0, v1) = Decoders.unpackAnnotation(cur);
            else (v0, v1) = PreviousDecoders.unpackAnnotation(cur);
            data = abi.encode(v0, v1);
        }
        else if (mode == 14) {
            bool v0;
            if (optimized) v0 = Decoders.tryConsumeEmpty(cur, bytes4(uint32(parameter)));
            else v0 = PreviousDecoders.tryConsumeEmpty(cur, bytes4(uint32(parameter)));
            data = abi.encode(v0);
        }
        else if (mode == 15) {
            bytes32 v0;
            if (optimized) v0 = Decoders.unpack32(cur, parameter);
            else v0 = PreviousDecoders.unpack32(cur, parameter);
            data = abi.encode(v0);
        }
    }
}
