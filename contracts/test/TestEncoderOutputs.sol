// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Encoder} from "../codec/Encoder.sol";

import {LegacyBuffers} from "./LegacyBuffers.sol";
contract TestEncoderOutputs {
    function fixedBlocks(uint kind, bytes32[5] calldata fields, uint count, uint capacity, bool previous)
        external view returns (uint gasUsed, bytes memory output)
    {
        Execution memory exec;
        uint beforeGas = gasleft();
        (exec.buffer, exec.output) = Encoder.init(capacity);
        for (uint j; j < count; ++j) {
            if (kind == 0) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 40, 40);
                    LegacyBlocks.writeAccount(exec.buffer, i, fields[0]);
                } else Executions.outputAccount(exec, fields[0]);
            }
            else if (kind == 1) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 40, 40);
                    LegacyBlocks.writeAsset(exec.buffer, i, fields[0]);
                } else Executions.outputAsset(exec, fields[0]);
            }
            else if (kind == 2) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 40, 40);
                    LegacyBlocks.writeNode(exec.buffer, i, uint(fields[0]));
                } else Executions.outputNode(exec, uint(fields[0]));
            }
            else if (kind == 3) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 40, 40);
                    LegacyBlocks.writeStatus(exec.buffer, i, uint(fields[0]));
                } else Executions.outputStatus(exec, uint(fields[0]));
            }
            else if (kind == 4) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 40, 40);
                    LegacyBlocks.writeLimits(exec.buffer, i, uint(fields[0]));
                } else Executions.outputLimits(exec, uint(fields[0]));
            }
            else if (kind == 5) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 72, 72);
                    LegacyBlocks.writeAmount(exec.buffer, i, fields[0], uint(fields[1]));
                } else Executions.outputAmount(exec, fields[0], uint(fields[1]));
            }
            else if (kind == 6) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 72, 72);
                    LegacyBlocks.writeBalance(exec.buffer, i, fields[0], uint(fields[1]));
                } else Executions.outputBalance(exec, fields[0], uint(fields[1]));
            }
            else if (kind == 7) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 72, 72);
                    LegacyBlocks.writeAssetLiability(exec.buffer, i, fields[0], fields[1]);
                } else Executions.outputAssetLiability(exec, fields[0], fields[1]);
            }
            else if (kind == 8) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 72, 72);
                    LegacyBlocks.writeAccountAsset(exec.buffer, i, fields[0], fields[1]);
                } else Executions.outputAccountAsset(exec, fields[0], fields[1]);
            }
            else if (kind == 9) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 72, 72);
                    LegacyBlocks.writeHostAsset(exec.buffer, i, uint(fields[0]), fields[1]);
                } else Executions.outputHostAsset(exec, uint(fields[0]), fields[1]);
            }
            else if (kind == 10) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 104, 104);
                    LegacyBlocks.writeAllocation(exec.buffer, i, uint(fields[0]), fields[1], uint(fields[2]));
                } else Executions.outputAllocation(exec, uint(fields[0]), fields[1], uint(fields[2]));
            }
            else if (kind == 11) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 104, 104);
                    LegacyBlocks.writeAllowance(exec.buffer, i, uint(fields[0]), fields[1], uint(fields[2]));
                } else Executions.outputAllowance(exec, uint(fields[0]), fields[1], uint(fields[2]));
            }
            else if (kind == 12) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 104, 104);
                    LegacyBlocks.writeCustody(exec.buffer, i, uint(fields[0]), fields[1], uint(fields[2]));
                } else Executions.outputCustody(exec, uint(fields[0]), fields[1], uint(fields[2]));
            }
            else if (kind == 13) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 104, 104);
                    LegacyBlocks.writeAccountAmount(exec.buffer, i, fields[0], fields[1], uint(fields[2]));
                } else Executions.outputAccountAmount(exec, fields[0], fields[1], uint(fields[2]));
            }
            else if (kind == 14) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 104, 104);
                    LegacyBlocks.writeHostAmount(exec.buffer, i, uint(fields[0]), fields[1], uint(fields[2]));
                } else Executions.outputHostAmount(exec, uint(fields[0]), fields[1], uint(fields[2]));
            }
            else if (kind == 15) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 104, 104);
                    LegacyBlocks.writeHostAccountAsset(exec.buffer, i, uint(fields[0]), fields[1], fields[2]);
                } else Executions.outputHostAccountAsset(exec, uint(fields[0]), fields[1], fields[2]);
            }
            else if (kind == 16) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 136, 136);
                    LegacyBlocks.writeQuote(exec.buffer, i, fields[0], uint(fields[1]), fields[2], uint(fields[3]));
                } else Executions.outputQuote(exec, fields[0], uint(fields[1]), fields[2], uint(fields[3]));
            }
            else if (kind == 17) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 136, 136);
                    LegacyBlocks.writeTransaction(exec.buffer, i, fields[0], fields[1], fields[2], uint(fields[3]));
                } else Executions.outputTransaction(exec, fields[0], fields[1], fields[2], uint(fields[3]));
            }
            else if (kind == 18) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 136, 136);
                    LegacyBlocks.writeHostAccountAmount(exec.buffer, i, uint(fields[0]), fields[1], fields[2], uint(fields[3]));
                } else Executions.outputHostAccountAmount(exec, uint(fields[0]), fields[1], fields[2], uint(fields[3]));
            }
            else if (kind == 19) {
                if (previous) {
                    uint i;
                    (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, 168, 168);
                    LegacyBlocks.writePosition(exec.buffer, i, fields[0], uint(fields[1]), fields[2], uint(fields[3]), fields[4]);
                } else Executions.outputPosition(exec, fields[0], uint(fields[1]), fields[2], uint(fields[3]), fields[4]);
            }
            else revert();
        }
        output = Executions.finish(exec);
        gasUsed = beforeGas - gasleft();
    }
    function payloads(uint kind, bytes calldata data, uint count, uint capacity, bool fromCalldata) external pure returns (bytes memory) {
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        for (uint j; j < count; ++j) {
            if (kind == 0) {
                if (fromCalldata) Executions.outputListWrap(exec, Cursors.wrap(data));
                else Executions.outputList(exec, data);
            } else if (kind == 1) {
                if (fromCalldata) Executions.outputBytesWrap(exec, Cursors.wrap(data));
                else Executions.outputBytes(exec, data);
            } else {
                if (fromCalldata) Executions.outputStringWrap(exec, Cursors.wrap(data));
                else Executions.outputString(exec, string(data));
            }
        }
        return Executions.finish(exec);
    }
}
