// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Cursors} from "../utils/Cursors.sol";
import {Buffers} from "../codec/Buffers.sol";
import {Writer, Writers} from "../codec/Writers.sol";
import {PreviousCursorNavigation} from "./PreviousCursorNavigation.sol";
import {PreviousRawWriters} from "./PreviousRawWriters.sol";

contract TestRawWriterCursorOptimization {
    bytes32 private constant a = bytes32(uint(0x1111));
    bytes32 private constant b = bytes32(uint(0x2222));
    bytes32 private constant c = bytes32(uint(0x3333));
    struct Config { uint mode; uint capacity; uint keep; uint count; bool aliasInput; }
    struct Result { uint usedGas; uint cursor; uint footprint; bytes output; }

    function navigate(bool optimized, bool consume, uint cur, uint amount, uint count)
        external view returns (uint usedGas, uint updated, uint position)
    {
        uint initial = gasleft();
        for (uint j; j < count; j++) {
            if (consume) {
                if (optimized) (cur, position) = Cursors.consume(cur, amount);
                else (cur, position) = PreviousCursorNavigation.consume(cur, amount);
            } else {
                if (optimized) cur = Cursors.advance(cur, amount);
                else cur = PreviousCursorNavigation.advance(cur, amount);
            }
        }
        usedGas = initial - gasleft();
        updated = cur;
    }

    function measure(bool optimized, Config calldata cfg, bytes calldata input)
        external view returns (Result memory r)
    {
        Writer memory writer = Writers.init(cfg.capacity);
        Writers.append(writer, hex"12345678");
        bytes memory data = cfg.aliasInput ? writer.dst : bytes(input);
        uint oldFree;
        assembly ("memory-safe") { oldFree := mload(0x40) }
        uint initial = gasleft();
        for (uint j; j < cfg.count; j++) {
            if (cfg.mode == 0) {
                if (optimized) Writers.append(writer, data);
                else PreviousRawWriters.append(writer, data);
            } else if (cfg.mode == 1) {
                if (optimized) Writers.copy(writer, input);
                else PreviousRawWriters.copy(writer, input);
            } else if (cfg.mode == 2) {
                if (optimized) Writers.append32(writer, a, cfg.keep);
                else PreviousRawWriters.append32(writer, a, cfg.keep);
            } else if (cfg.mode == 3) {
                if (optimized) Writers.append64(writer, a, b, cfg.keep);
                else PreviousRawWriters.append64(writer, a, b, cfg.keep);
            } else {
                if (optimized) Writers.append96(writer, a, b, c, cfg.keep);
                else PreviousRawWriters.append96(writer, a, b, c, cfg.keep);
            }
        }
        r.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(r, 64), sub(mload(0x40), oldFree)) }
        r.cursor = writer.cur;
        // Return the entire backing allocation, including writes beyond keep.
        r.output = writer.dst;
    }
}
