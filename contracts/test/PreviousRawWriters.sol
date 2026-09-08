// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Buffers} from "../codec/Buffers.sol";
import {Writer} from "../codec/Writers.sol";
// Frozen baseline for differential benchmarks.
library PreviousRawWriters {
    function reserve(Writer memory writer, uint advance, uint touch) private pure returns (uint i) {
        (writer.cur, writer.dst, i) = Buffers.reserve(writer.cur, writer.dst, advance, touch);
    }
    function append(Writer memory writer, bytes memory data) internal pure {
        uint i = reserve(writer, data.length, data.length);
        Buffers.write(writer.dst, i, data);
    }
    function append32(Writer memory writer, bytes32 value, uint keep) internal pure {
        uint i = reserve(writer, keep, 32);
        Buffers.write32(writer.dst, i, value);
    }
    function append64(Writer memory writer, bytes32 a, bytes32 b, uint keep) internal pure {
        uint i = reserve(writer, 32 + keep, 64);
        Buffers.write64(writer.dst, i, a, b);
    }
    function append96(Writer memory writer, bytes32 a, bytes32 b, bytes32 c, uint keep) internal pure {
        uint i = reserve(writer, 64 + keep, 96);
        Buffers.write96(writer.dst, i, a, b, c);
    }
    function copy(Writer memory writer, bytes calldata data) internal pure {
        uint i = reserve(writer, data.length, data.length);
        Buffers.copy(writer.dst, i, data);
    }
}
