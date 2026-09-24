// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Execution, Executions} from "../execution/Execution.sol";
import {PreviousExecutions} from "./PreviousExecutions.sol";
import {Specs} from "../codec/Specs.sol";
import {Blocks} from "../codec/Blocks.sol";

contract TestExecutionOptimization {
    struct Config {
        uint inputStart;
        uint inputEnd;
        uint stateStart;
        uint stateEnd;
        uint flags;
        uint budget;
        uint parameter;
        uint repetitions;
    }
    struct Result { uint usedGas; uint decoders; uint budget; bytes data; }

    function measure(bool optimized, uint mode, bytes calldata state, bytes calldata input, Config calldata cfg)
        external view returns (Result memory result) {
        Execution memory exec;
        uint a; uint b;
        assembly ("memory-safe") { a := input.offset b := state.offset }
        exec.decoders = (a + cfg.inputStart) | ((a + cfg.inputEnd) << 32)
            | ((b + cfg.stateStart) << 64) | ((b + cfg.stateEnd) << 96) | (cfg.flags << 128);
        exec.budget = cfg.budget;
        uint initial = gasleft();
        for (uint j; j < cfg.repetitions; j++) result.data = step(optimized, mode, exec, cfg.parameter);
        result.usedGas = initial - gasleft();
        result.decoders = exec.decoders;
        result.budget = exec.budget;
    }

    function step(bool optimized, uint mode, Execution memory exec, uint parameter) private pure returns(bytes memory data) {
        if (mode == 0) {
            bytes calldata v0;
            if (optimized) v0 = Executions.unpackBytes(exec);
            else v0 = PreviousExecutions.unpackBytes(exec);
            data = abi.encode(v0);
        }
        else if (mode == 1) {
            uint v0; uint v1; bytes calldata v2;
            if (optimized) (v0, v1, v2) = Executions.unpackStep(exec);
            else (v0, v1, v2) = PreviousExecutions.unpackStep(exec);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 2) {
            uint v0; uint v1;
            if (optimized) (v0, v1) = Executions.consume(exec, parameter);
            else (v0, v1) = PreviousExecutions.consume(exec, parameter);
            data = abi.encode(v0, v1);
        }
        else if (mode == 3) {
            uint v0; uint v1;
            if (optimized) (v0, v1) = Executions.consume(exec, bytes4(uint32(parameter)));
            else (v0, v1) = PreviousExecutions.consume(exec, bytes4(uint32(parameter)));
            data = abi.encode(v0, v1);
        }
        else if (mode == 4) {
            bytes calldata v0;
            if (optimized) v0 = Executions.unpackRaw(exec, parameter);
            else v0 = PreviousExecutions.unpackRaw(exec, parameter);
            data = abi.encode(v0);
        }
        else if (mode == 5) {
            string memory v0;
            if (optimized) v0 = Executions.unpackString(exec);
            else v0 = PreviousExecutions.unpackString(exec);
            data = abi.encode(v0);
        }
        else if (mode == 6) {
            bytes32 v0; bytes calldata v1; bytes calldata v2;
            if (optimized) (v0, v1, v2) = Executions.unpackContext(exec);
            else (v0, v1, v2) = PreviousExecutions.unpackContext(exec);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 7) {
            bytes calldata v0; bytes calldata v1;
            if (optimized) (v0, v1) = Executions.unpackRelay(exec);
            else (v0, v1) = PreviousExecutions.unpackRelay(exec);
            data = abi.encode(v0, v1);
        }
        else if (mode == 8) {
            bytes32 v0; string memory v1;
            if (optimized) (v0, v1) = Executions.unpackLabel(exec);
            else (v0, v1) = PreviousExecutions.unpackLabel(exec);
            data = abi.encode(v0, v1);
        }
        else if (mode == 9) {
            uint v0; string memory v1;
            if (optimized) (v0, v1) = Executions.unpackSchema(exec);
            else (v0, v1) = PreviousExecutions.unpackSchema(exec);
            data = abi.encode(v0, v1);
        }
        else if (mode == 10) {
            uint v0; uint v1; bytes32 v2; bytes calldata v3;
            if (optimized) (v0, v1, v2, v3) = Executions.unpackRecover(exec);
            else (v0, v1, v2, v3) = PreviousExecutions.unpackRecover(exec);
            data = abi.encode(v0, v1, v2, v3);
        }
        else if (mode == 11) {
            uint v0; uint v1; bytes calldata v2;
            if (optimized) (v0, v1, v2) = Executions.unpackCall(exec);
            else (v0, v1, v2) = PreviousExecutions.unpackCall(exec);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 12) {
            uint v0; uint v1; bytes calldata v2;
            if (optimized) (v0, v1, v2) = Executions.unpackDispatch(exec);
            else (v0, v1, v2) = PreviousExecutions.unpackDispatch(exec);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 13) {
            uint v0; bytes calldata v1;
            if (optimized) (v0, v1) = Executions.unpackAnnotation(exec);
            else (v0, v1) = PreviousExecutions.unpackAnnotation(exec);
            data = abi.encode(v0, v1);
        }
        else if (mode == 14) {
            bool v0;
            if (optimized) v0 = Executions.tryConsumeEmpty(exec, bytes4(uint32(parameter)));
            else v0 = PreviousExecutions.tryConsumeEmpty(exec, bytes4(uint32(parameter)));
            data = abi.encode(v0);
        }
        else if (mode == 15) {
            bytes calldata v0;
            if (optimized) v0 = Executions.rawState(exec);
            else v0 = PreviousExecutions.rawState(exec);
            data = abi.encode(v0);
        }
        else if (mode == 16) {
            bytes calldata v0;
            if (optimized) v0 = Executions.takeRawState(exec);
            else v0 = PreviousExecutions.takeRawState(exec);
            data = abi.encode(v0);
        }
        else if (mode == 17) {
            bytes calldata v0;
            if (optimized) v0 = Executions.rawInput(exec);
            else v0 = PreviousExecutions.rawInput(exec);
            data = abi.encode(v0);
        }
        else if (mode == 18) {
            bytes calldata v0;
            if (optimized) v0 = Executions.takeRawInput(exec);
            else v0 = PreviousExecutions.takeRawInput(exec);
            data = abi.encode(v0);
        }
        else if (mode == 19) {
            bytes calldata v0;
            if (optimized) v0 = Executions.takeRawBalances(exec);
            else v0 = PreviousExecutions.takeRawBalances(exec);
            data = abi.encode(v0);
        }
        else if (mode == 20) {
            bytes32 v0;
            if (optimized) v0 = Executions.unpack32(exec, parameter);
            else v0 = PreviousExecutions.unpack32(exec, parameter);
            data = abi.encode(v0);
        }
        else if (mode == 21) {
            uint v0;
            if (optimized) v0 = Executions.useValue(exec, parameter);
            else v0 = PreviousExecutions.useValue(exec, parameter);
            data = abi.encode(v0);
        }
    }
}
