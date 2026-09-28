// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks, Cursors} from "../Codec.sol";

/// @dev Tests the uniform public unpacking contract directly, including discarded returns.
contract CursorUniform64 {
    function inspect(bytes calldata source, uint length, uint offset, uint metadata, bytes4 key)
        external pure returns (bytes32[] memory values, uint[] memory children, uint next, uint original, uint baseAbs)
    {
        require(length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        original = cur;
        (bytes32 v0, bytes32 v1, uint nextCur) = Blocks.unpack64(cur, key);
        values = new bytes32[](2);
        children = new uint[](0);
        values[0] = bytes32(v0);
        values[1] = bytes32(v1);
        next = nextCur;
    }
    function onlyValues(bytes calldata source, bytes4 key) external pure returns (uint sum) {
        uint cur = Cursors.wrap(source);
        (bytes32 v0, bytes32 v1, ) = Blocks.unpack64(cur, key);
        unchecked { sum = uint(v0) + uint(v1); }
    }
    function measure(bytes calldata source, bytes4 key) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 v0, bytes32 v1, uint nextCur) = Blocks.unpack64(cur, key);
            unchecked { sum += uint(v0) + uint(v1); }
            cur = nextCur;
        }
        gasUsed = beforeGas - gasleft();
    }
}

contract CursorUniform160 {
    function inspect(bytes calldata source, uint length, uint offset, uint metadata, bytes4 key)
        external pure returns (bytes32[] memory values, uint[] memory children, uint next, uint original, uint baseAbs)
    {
        require(length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        original = cur;
        (bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, uint nextCur) = Blocks.unpack160(cur, key);
        values = new bytes32[](5);
        children = new uint[](0);
        values[0] = bytes32(v0);
        values[1] = bytes32(v1);
        values[2] = bytes32(v2);
        values[3] = bytes32(v3);
        values[4] = bytes32(v4);
        next = nextCur;
    }
    function onlyValues(bytes calldata source, bytes4 key) external pure returns (uint sum) {
        uint cur = Cursors.wrap(source);
        (bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, ) = Blocks.unpack160(cur, key);
        unchecked { sum = uint(v0) + uint(v1) + uint(v2) + uint(v3) + uint(v4); }
    }
    function measure(bytes calldata source, bytes4 key) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, uint nextCur) = Blocks.unpack160(cur, key);
            unchecked { sum += uint(v0) + uint(v1) + uint(v2) + uint(v3) + uint(v4); }
            cur = nextCur;
        }
        gasUsed = beforeGas - gasleft();
    }
}

contract CursorUniformBalance {
    function inspect(bytes calldata source, uint length, uint offset, uint metadata, bytes4 key)
        external pure returns (bytes32[] memory values, uint[] memory children, uint next, uint original, uint baseAbs)
    {
        require(length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        original = cur;
        (bytes32 v0, uint v1, uint nextCur) = Blocks.unpackBalance(cur);
        values = new bytes32[](2);
        children = new uint[](0);
        values[0] = bytes32(v0);
        values[1] = bytes32(v1);
        next = nextCur;
    }
    function onlyValues(bytes calldata source, bytes4 key) external pure returns (uint sum) {
        uint cur = Cursors.wrap(source);
        (bytes32 v0, uint v1, ) = Blocks.unpackBalance(cur);
        unchecked { sum = uint(v0) + uint(v1); }
    }
    function measure(bytes calldata source, bytes4 key) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 v0, uint v1, uint nextCur) = Blocks.unpackBalance(cur);
            unchecked { sum += uint(v0) + uint(v1); }
            cur = nextCur;
        }
        gasUsed = beforeGas - gasleft();
    }
}

contract CursorUniformStep {
    function inspect(bytes calldata source, uint length, uint offset, uint metadata, bytes4 key)
        external pure returns (bytes32[] memory values, uint[] memory children, uint next, uint original, uint baseAbs)
    {
        require(length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        original = cur;
        (uint v0, uint v1, uint child0Cur, uint nextCur) = Blocks.unpackStep(cur);
        values = new bytes32[](2);
        children = new uint[](1);
        values[0] = bytes32(v0);
        values[1] = bytes32(v1);
        children[0] = child0Cur;
        next = nextCur;
    }
    function onlyValues(bytes calldata source, bytes4 key) external pure returns (uint sum) {
        uint cur = Cursors.wrap(source);
        (uint v0, uint v1, , ) = Blocks.unpackStep(cur);
        unchecked { sum = uint(v0) + uint(v1); }
    }
    function measure(bytes calldata source, bytes4 key) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (uint v0, uint v1, uint child0Cur, uint nextCur) = Blocks.unpackStep(cur);
            unchecked { sum += uint(v0) + uint(v1) + uint32(child0Cur >> 32) - uint32(child0Cur); }
            cur = nextCur;
        }
        gasUsed = beforeGas - gasleft();
    }
}

contract CursorUniformRelay {
    function inspect(bytes calldata source, uint length, uint offset, uint metadata, bytes4 key)
        external pure returns (bytes32[] memory values, uint[] memory children, uint next, uint original, uint baseAbs)
    {
        require(length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        original = cur;
        (uint child0Cur, uint child1Cur, uint nextCur) = Blocks.unpackRelay(cur);
        values = new bytes32[](0);
        children = new uint[](2);
        children[0] = child0Cur;
        children[1] = child1Cur;
        next = nextCur;
    }
    function onlyValues(bytes calldata source, bytes4 key) external pure returns (uint sum) {
        uint cur = Cursors.wrap(source);
        Blocks.unpackRelay(cur);
    }
    function measure(bytes calldata source, bytes4 key) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (uint child0Cur, uint child1Cur, uint nextCur) = Blocks.unpackRelay(cur);
            unchecked { sum += uint32(child0Cur >> 32) - uint32(child0Cur) + uint32(child1Cur >> 32) - uint32(child1Cur); }
            cur = nextCur;
        }
        gasUsed = beforeGas - gasleft();
    }
}

contract CursorUniformContext {
    function inspect(bytes calldata source, uint length, uint offset, uint metadata, bytes4 key)
        external pure returns (bytes32[] memory values, uint[] memory children, uint next, uint original, uint baseAbs)
    {
        require(length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        original = cur;
        (bytes32 v0, uint child0Cur, uint child1Cur, uint nextCur) = Blocks.unpackContext(cur);
        values = new bytes32[](1);
        children = new uint[](2);
        values[0] = bytes32(v0);
        children[0] = child0Cur;
        children[1] = child1Cur;
        next = nextCur;
    }
    function onlyValues(bytes calldata source, bytes4 key) external pure returns (uint sum) {
        uint cur = Cursors.wrap(source);
        (bytes32 v0, , , ) = Blocks.unpackContext(cur);
        unchecked { sum = uint(v0); }
    }
    function measure(bytes calldata source, bytes4 key) external view returns (uint gasUsed, uint sum, uint cur) {
        cur = Cursors.wrap(source) | (uint(0xa5) << 64);
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (bytes32 v0, uint child0Cur, uint child1Cur, uint nextCur) = Blocks.unpackContext(cur);
            unchecked { sum += uint(v0) + uint32(child0Cur >> 32) - uint32(child0Cur) + uint32(child1Cur >> 32) - uint32(child1Cur); }
            cur = nextCur;
        }
        gasUsed = beforeGas - gasleft();
    }
}
