// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {Blocks, Cursors, Keys} from "../Codec.sol";
import {Position} from "../core/Types.sol";
import {OutOfBounds} from "../utils/Errors.sol";

import {CursorFurtherCandidates} from "./CursorFurtherCandidates.sol";
contract CursorConsumerEnvelopePackedLT {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur < exhaustedCur) {
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
        while (cur < exhaustedCur) {
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

contract CursorConsumerEnvelopeClean {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < (cur >> 32)) {
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

contract CursorConsumerEnvelopeRepack {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorFurtherCandidates.unpackBalanceRepack(cur);
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

contract CursorConsumerEnvelopeReadFirst {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorFurtherCandidates.unpackBalanceReadFirst(cur);
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

contract CursorConsumerEnvelopeBytes {
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
            uint payloadCur;
            (payloadCur, cur) = CursorFurtherCandidates.unpackBytes(cur);
            (uint value, uint children) = balances(payloadCur);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeBytesPackedLT {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur < exhaustedCur) {
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
        while (cur < exhaustedCur) {
            uint payloadCur;
            (payloadCur, cur) = CursorFurtherCandidates.unpackBytes(cur);
            (uint value, uint children) = balances(payloadCur);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeEnterNow {
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

contract CursorConsumerStepPackedLT {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur < exhaustedCur) {
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
        while (cur < exhaustedCur) {
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            (uint childSum, uint children) = balances(inputCur);
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepClean {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < (cur >> 32)) {
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
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            (uint childSum, uint children) = balances(inputCur);
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepRepack {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorFurtherCandidates.unpackBalanceRepack(cur);
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

contract CursorConsumerStepReadFirst {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorFurtherCandidates.unpackBalanceReadFirst(cur);
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

contract CursorConsumerChainPackedLT {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(uint(1)), 7, bytes32(uint(2)), 3, bytes32(0));
        uint beforeGas = gasleft();
        uint exhaustedCur = (cur & ~uint(type(uint32).max)) | uint32(cur >> 32);
        while (cur < exhaustedCur) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = Blocks.unpackBalance(cur);
            cur = Blocks.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainClean {
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
            cur = Blocks.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainRepack {
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
            (asset, amount, cur) = CursorFurtherCandidates.unpackBalanceRepack(cur);
            cur = Blocks.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainReadFirst {
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
            (asset, amount, cur) = CursorFurtherCandidates.unpackBalanceReadFirst(cur);
            cur = Blocks.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeSigned {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorFurtherCandidates.unpackBalanceSigned(cur);
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

contract CursorConsumerEnvelopeAdvanceFirst {
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
            (uint blockCur, ) = Blocks.take(cur, Keys.Bytes);
            uint payloadCur;
            unchecked { payloadCur = blockCur + 8; }
            // Selection keeps its own range; resume the enclosing stream at its end.
            cur = (cur & ~uint(type(uint32).max)) | uint32(blockCur >> 32);
            (uint value, uint children) = balances(payloadCur);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeChildReturns {
    function balances(uint cur) private pure returns (uint sum, uint count, uint nextCur) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = Blocks.unpackBalance(cur);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        nextCur = cur;
    }
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
            (uint value, uint children, uint afterCur) = balances(payloadCur);
            // Selection keeps its own range; resume the enclosing stream at its end.
            cur = (cur & ~uint(type(uint32).max)) | uint32(afterCur);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepSigned {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorFurtherCandidates.unpackBalanceSigned(cur);
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

contract CursorConsumerChainSigned {
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
            (asset, amount, cur) = CursorFurtherCandidates.unpackBalanceSigned(cur);
            cur = Blocks.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeHybrid {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint abs = uint32(cur);
        uint endAbs = uint32(cur >> 32);
        while (abs < endAbs) {
            (bytes32 asset, uint amount) = CursorFurtherCandidates.unpackBalanceAt(abs, endAbs);
            unchecked { abs += 72; sum += uint(asset) + amount; ++count; }
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

contract CursorConsumerStepHybrid {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint abs = uint32(cur);
        uint endAbs = uint32(cur >> 32);
        while (abs < endAbs) {
            (bytes32 asset, uint amount) = CursorFurtherCandidates.unpackBalanceAt(abs, endAbs);
            unchecked { abs += 72; sum += uint(asset) + amount; ++count; }
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

contract CursorConsumerEnvelopeBytesComposed {
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
            uint payloadCur;
            (payloadCur, cur) = CursorFurtherCandidates.unpackBytesComposed(cur);
            (uint value, uint children) = balances(payloadCur);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerEnvelopeHybridNext {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint abs = uint32(cur);
        uint endAbs = uint32(cur >> 32);
        while (abs < endAbs) {
            bytes32 asset; uint amount;
            (asset, amount, abs) = CursorFurtherCandidates.unpackBalanceNextAt(abs, endAbs);
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

contract CursorConsumerEnvelopeBytesHybrid {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint abs = uint32(cur);
        uint endAbs = uint32(cur >> 32);
        while (abs < endAbs) {
            bytes32 asset; uint amount;
            (asset, amount, abs) = CursorFurtherCandidates.unpackBalanceNextAt(abs, endAbs);
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
            uint payloadCur;
            (payloadCur, cur) = CursorFurtherCandidates.unpackBytes(cur);
            (uint value, uint children) = balances(payloadCur);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepHybridNext {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        uint abs = uint32(cur);
        uint endAbs = uint32(cur >> 32);
        while (abs < endAbs) {
            bytes32 asset; uint amount;
            (asset, amount, abs) = CursorFurtherCandidates.unpackBalanceNextAt(abs, endAbs);
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
