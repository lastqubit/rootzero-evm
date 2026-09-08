// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Buffers} from "../codec/Buffers.sol";
import {PreviousBufferReserve} from "./PreviousBufferReserve.sol";

contract TestBufferReserveOptimization {
    struct Config { uint cursor; uint backing; uint advance; uint touch; }
    struct Result { uint usedGas; uint cursor; uint position; uint footprint; bytes output; }

    function measure(bool optimized, Config calldata cfg) external view returns (Result memory r) {
        bytes memory buffer = new bytes(cfg.backing);
        // A nonzero prefix detects accidental loss during resize.
        for (uint j; j < buffer.length; j++) buffer[j] = bytes1(uint8(j + 1));
        uint oldFree;
        assembly ("memory-safe") { oldFree := mload(0x40) }
        // Poison a bounded future allocation region. Both reserve implementations
        // must still return zero-filled unwritten memory after allocating/resizing.
        assembly {
            for { let q := oldFree } lt(q, add(oldFree, 20000)) { q := add(q, 32) } { mstore(q, not(0)) }
        }
        uint initial = gasleft();
        if (optimized) (r.cursor, r.output, r.position) = Buffers.reserve(cfg.cursor, buffer, cfg.advance, cfg.touch);
        else (r.cursor, r.output, r.position) = PreviousBufferReserve.reserve(cfg.cursor, buffer, cfg.advance, cfg.touch);
        r.usedGas = initial - gasleft();
        assembly ("memory-safe") { mstore(add(r, 96), sub(mload(0x40), oldFree)) }
    }
}
