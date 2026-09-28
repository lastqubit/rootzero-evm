// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {Blocks, Cursors, Keys} from "../Codec.sol";
import {Position} from "../core/Types.sol";
import {OutOfBounds} from "../utils/Errors.sol";

import {CursorConsumerPrimitives, CursorConsumerFused, CursorConsumerCompact} from "./CursorConsumerCandidates.sol";

// Test-only consumers keep the production cursor API and logical checks.
contract CursorConsumerEnvelopeCached {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint endAbs = uint32(cur >> 32);
        while (uint32(cur) < endAbs) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = Blocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        uint endAbs = uint32(cur >> 32);
        while (uint32(cur) < endAbs) {
            (uint blockCur, ) = Blocks.take(cur, Keys.Bytes);
            uint payloadCur;
            unchecked { payloadCur = blockCur + 8; }
            (uint value, uint children) = balances(payloadCur);
            // Selection keeps its own range; resume the enclosing stream at its end.
            cur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopePrimitives {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerPrimitives.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint blockCur = CursorConsumerPrimitives.take(cur, Keys.Bytes);
            uint payloadCur;
            unchecked { payloadCur = blockCur + 8; }
            (uint value, uint children) = balances(payloadCur);
            // Selection keeps its own range; resume the enclosing stream at its end.
            cur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeFused {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerFused.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint blockCur = CursorConsumerFused.take(cur, Keys.Bytes);
            uint payloadCur;
            unchecked { payloadCur = blockCur + 8; }
            (uint value, uint children) = balances(payloadCur);
            // Selection keeps its own range; resume the enclosing stream at its end.
            cur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopePrimitiveCached {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint endAbs = uint32(cur >> 32);
        while (uint32(cur) < endAbs) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerPrimitives.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        uint endAbs = uint32(cur >> 32);
        while (uint32(cur) < endAbs) {
            uint blockCur = CursorConsumerPrimitives.take(cur, Keys.Bytes);
            uint payloadCur;
            unchecked { payloadCur = blockCur + 8; }
            (uint value, uint children) = balances(payloadCur);
            // Selection keeps its own range; resume the enclosing stream at its end.
            cur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeEnter {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = Blocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (uint payloadCur, ) = Blocks.unpack(cur, Keys.Bytes);
            (uint value, uint children) = balances(payloadCur);
            // Selection keeps its own range; resume the enclosing stream at its end.
            cur = (cur & ~uint(type(uint32).max)) | uint32(payloadCur >> 32);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepCached {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint endAbs = uint32(cur >> 32);
        while (uint32(cur) < endAbs) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = Blocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        uint endAbs = uint32(cur >> 32);
        while (uint32(cur) < endAbs) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            (uint childSum, uint children) = balances(inputCur);
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepPrimitives {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerPrimitives.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            (uint childSum, uint children) = balances(inputCur);
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepFused {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerFused.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            (uint childSum, uint children) = balances(inputCur);
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepPrimitiveCached {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint endAbs = uint32(cur >> 32);
        while (uint32(cur) < endAbs) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerPrimitives.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        uint endAbs = uint32(cur >> 32);
        while (uint32(cur) < endAbs) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            (uint childSum, uint children) = balances(inputCur);
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainCached {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(uint(1)), 7, bytes32(uint(2)), 3, bytes32(0));
        uint beforeGas = gasleft();
        uint endAbs = uint32(cur >> 32);
        while (uint32(cur) < endAbs) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = Blocks.unpackBalance(cur);
            cur = Blocks.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainPrimitives {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(uint(1)), 7, bytes32(uint(2)), 3, bytes32(0));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerPrimitives.unpackBalance(cur);
            cur = CursorConsumerPrimitives.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainFused {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(uint(1)), 7, bytes32(uint(2)), 3, bytes32(0));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerFused.unpackBalance(cur);
            cur = CursorConsumerFused.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainPrimitiveCached {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(uint(1)), 7, bytes32(uint(2)), 3, bytes32(0));
        uint beforeGas = gasleft();
        uint endAbs = uint32(cur >> 32);
        while (uint32(cur) < endAbs) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerPrimitives.unpackBalance(cur);
            cur = CursorConsumerPrimitives.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeCompact {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerCompact.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint blockCur = CursorConsumerCompact.take(cur, Keys.Bytes);
            uint payloadCur;
            unchecked { payloadCur = blockCur + 8; }
            (uint value, uint children) = balances(payloadCur);
            // Selection keeps its own range; resume the enclosing stream at its end.
            cur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeTerminal {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur != exhaustedCur) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = Blocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur != exhaustedCur) {
            (uint blockCur, ) = Blocks.take(cur, Keys.Bytes);
            uint payloadCur;
            unchecked { payloadCur = blockCur + 8; }
            (uint value, uint children) = balances(payloadCur);
            // Selection keeps its own range; resume the enclosing stream at its end.
            cur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeFusedTerminal {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur != exhaustedCur) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerFused.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur != exhaustedCur) {
            uint blockCur = CursorConsumerFused.take(cur, Keys.Bytes);
            uint payloadCur;
            unchecked { payloadCur = blockCur + 8; }
            (uint value, uint children) = balances(payloadCur);
            // Selection keeps its own range; resume the enclosing stream at its end.
            cur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeInline {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            (uint blockCur, ) = Blocks.take(cur, Keys.Bytes);
            uint payloadCur;
            unchecked { payloadCur = blockCur + 8; }
            uint value; uint children;
            while (uint32(payloadCur) < uint32(payloadCur >> 32)) {
                bytes32 asset; uint amount;
                (asset, amount, payloadCur) = Blocks.unpackBalance(payloadCur);
                unchecked { value += uint(asset) + amount; ++children; }
            }
            // Selection keeps its own range; resume the enclosing stream at its end.
            cur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepCompact {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerCompact.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            (uint childSum, uint children) = balances(inputCur);
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepTerminal {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur != exhaustedCur) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = Blocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur != exhaustedCur) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            (uint childSum, uint children) = balances(inputCur);
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepFusedTerminal {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur != exhaustedCur) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerFused.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur != exhaustedCur) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            (uint childSum, uint children) = balances(inputCur);
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepInline {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            uint childSum; uint children;
            while (uint32(inputCur) < uint32(inputCur >> 32)) {
                bytes32 asset; uint amount;
                (asset, amount, inputCur) = Blocks.unpackBalance(inputCur);
                unchecked { childSum += uint(asset) + amount; ++children; }
            }
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainCompact {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(uint(1)), 7, bytes32(uint(2)), 3, bytes32(0));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerCompact.unpackBalance(cur);
            cur = CursorConsumerCompact.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainTerminal {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(uint(1)), 7, bytes32(uint(2)), 3, bytes32(0));
        uint beforeGas = gasleft();
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur != exhaustedCur) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = Blocks.unpackBalance(cur);
            cur = Blocks.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainFusedTerminal {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(uint(1)), 7, bytes32(uint(2)), 3, bytes32(0));
        uint beforeGas = gasleft();
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur != exhaustedCur) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerFused.unpackBalance(cur);
            cur = CursorConsumerFused.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainBalanceOnly {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(uint(1)), 7, bytes32(uint(2)), 3, bytes32(0));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorConsumerFused.unpackBalance(cur);
            cur = Blocks.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainExpectOnly {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(uint(1)), 7, bytes32(uint(2)), 3, bytes32(0));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = Blocks.unpackBalance(cur);
            cur = CursorConsumerFused.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}
