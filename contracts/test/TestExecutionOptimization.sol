// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {PreviousExecutions} from "./PreviousExecutions.sol";
import {Specs} from "../codec/Specs.sol";

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
        exec.input = (a + cfg.inputStart) | ((a + cfg.inputEnd) << 32) | (((cfg.flags >> 1) & 1) << 64);
        exec.state = (b + cfg.stateStart) | ((b + cfg.stateEnd) << 32) | ((cfg.flags & ~uint(2)) << 64);
        exec.budget = cfg.budget;
        uint initial = gasleft();
        for (uint j; j < cfg.repetitions; j++) result.data = step(optimized, mode, exec, cfg.parameter);
        result.usedGas = initial - gasleft();
        // Preserve the test result format; serialization is outside the measured region.
        result.decoders = uint64(exec.input) | (uint(uint64(exec.state)) << 64)
            | ((exec.state >> 64) << 128) | ((exec.input >> 64) << 129);
        result.budget = exec.budget;
    }

    function step(bool optimized, uint mode, Execution memory exec, uint parameter) private pure returns(bytes memory data) {
        if (mode == 0) {
            bytes calldata v0;
            if (optimized) v0 = Blocks.toBytes(Executions.unpackBytes(exec));
            else v0 = PreviousExecutions.unpackBytes(exec);
            data = abi.encode(v0);
        }
        else if (mode == 1) {
            uint v0; uint v1; bytes calldata v2;
            if (optimized) {
                uint v2Cur;
                (v0, v1, v2Cur) = Executions.unpackStep(exec);
                v2 = Blocks.toBytes(v2Cur);
            }
            else (v0, v1, v2) = PreviousExecutions.unpackStep(exec);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 2) {
            uint v0; uint v1;
            if (optimized) {
                uint payloadCur = Executions.unpack(exec, parameter);
                v0 = uint32(payloadCur);
                v1 = uint32(payloadCur >> 32);
            }
            else (v0, v1) = PreviousExecutions.consume(exec, parameter);
            data = abi.encode(v0, v1);
        }
        else if (mode == 3) {
            uint v0; uint v1;
            if (optimized) {
                uint payloadCur = Executions.unpack(exec, bytes4(uint32(parameter)));
                v0 = uint32(payloadCur);
                v1 = uint32(payloadCur >> 32);
            }
            else (v0, v1) = PreviousExecutions.consume(exec, bytes4(uint32(parameter)));
            data = abi.encode(v0, v1);
        }
        else if (mode == 4) {
            bytes calldata v0;
            if (optimized) v0 = Blocks.toBytes(Executions.unpack(exec, parameter));
            else v0 = PreviousExecutions.unpackRaw(exec, parameter);
            data = abi.encode(v0);
        }
        else if (mode == 5) {
            string memory v0;
            if (optimized) v0 = Blocks.toString(Executions.unpackString(exec));
            else v0 = PreviousExecutions.unpackString(exec);
            data = abi.encode(v0);
        }
        else if (mode == 6) {
            bytes32 v0; bytes calldata v1; bytes calldata v2;
            if (optimized) {
                uint v1Cur;
                uint v2Cur;
                (v0, v1Cur, v2Cur) = Executions.unpackContext(exec);
                v1 = Blocks.toBytes(v1Cur);
                v2 = Blocks.toBytes(v2Cur);
            }
            else (v0, v1, v2) = PreviousExecutions.unpackContext(exec);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 7) {
            bytes calldata v0; bytes calldata v1;
            if (optimized) {
                uint v0Cur;
                uint v1Cur;
                (v0Cur, v1Cur) = Executions.unpackRelay(exec);
                v0 = Blocks.toBytes(v0Cur);
                v1 = Blocks.toBytes(v1Cur);
            }
            else (v0, v1) = PreviousExecutions.unpackRelay(exec);
            data = abi.encode(v0, v1);
        }
        else if (mode == 8) {
            bytes32 v0; string memory v1;
            if (optimized) {
                uint v1Cur;
                (v0, v1Cur) = Executions.unpackLabel(exec);
                v1 = Blocks.toString(v1Cur);
            }
            else (v0, v1) = PreviousExecutions.unpackLabel(exec);
            data = abi.encode(v0, v1);
        }
        else if (mode == 9) {
            uint v0; string memory v1;
            if (optimized) {
                uint v1Cur;
                (v0, v1Cur) = Executions.unpackSchema(exec);
                v1 = Blocks.toString(v1Cur);
            }
            else (v0, v1) = PreviousExecutions.unpackSchema(exec);
            data = abi.encode(v0, v1);
        }
        else if (mode == 10) {
            uint v0; uint v1; bytes32 v2; bytes calldata v3;
            if (optimized) {
                uint v3Cur;
                (v0, v1, v2, v3Cur) = Executions.unpackRecover(exec);
                v3 = Blocks.toBytes(v3Cur);
            }
            else (v0, v1, v2, v3) = PreviousExecutions.unpackRecover(exec);
            data = abi.encode(v0, v1, v2, v3);
        }
        else if (mode == 11) {
            uint v0; uint v1; bytes calldata v2;
            if (optimized) {
                uint v2Cur;
                (v0, v1, v2Cur) = Executions.unpackCall(exec);
                v2 = Blocks.toBytes(v2Cur);
            }
            else (v0, v1, v2) = PreviousExecutions.unpackCall(exec);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 12) {
            uint v0; uint v1; bytes calldata v2;
            if (optimized) {
                uint v2Cur;
                (v0, v1, v2Cur) = Executions.unpackDispatch(exec);
                v2 = Blocks.toBytes(v2Cur);
            }
            else (v0, v1, v2) = PreviousExecutions.unpackDispatch(exec);
            data = abi.encode(v0, v1, v2);
        }
        else if (mode == 13) {
            uint v0; bytes calldata v1;
            if (optimized) {
                uint v1Cur;
                (v0, v1Cur) = Executions.unpackAnnotation(exec);
                v1 = Blocks.toBytes(v1Cur);
            }
            else (v0, v1) = PreviousExecutions.unpackAnnotation(exec);
            data = abi.encode(v0, v1);
        }
        // Retained raw-access measurements use only the frozen legacy API.
        else if (mode == 14) {
            bytes calldata v0;
            v0 = PreviousExecutions.rawState(exec);
            data = abi.encode(v0);
        }
        else if (mode == 15) {
            bytes calldata v0;
            v0 = PreviousExecutions.takeRawState(exec);
            data = abi.encode(v0);
        }
        else if (mode == 16) {
            bytes calldata v0;
            v0 = PreviousExecutions.rawInput(exec);
            data = abi.encode(v0);
        }
        else if (mode == 17) {
            bytes calldata v0;
            v0 = PreviousExecutions.takeRawInput(exec);
            data = abi.encode(v0);
        }
        else if (mode == 18) {
            bytes calldata v0;
            if (optimized) v0 = Blocks.toBytes(Executions.takeBalances(exec));
            else v0 = PreviousExecutions.takeRawBalances(exec);
            data = abi.encode(v0);
        }
        else if (mode == 19) {
            bytes32 v0;
            if (optimized) v0 = Executions.unpack32(exec, parameter);
            else v0 = PreviousExecutions.unpack32(exec, parameter);
            data = abi.encode(v0);
        }
        else if (mode == 20) {
            uint v0;
            if (optimized) v0 = Executions.useValue(exec, parameter);
            else v0 = PreviousExecutions.useValue(exec, parameter);
            data = abi.encode(v0);
        }
    }
}
