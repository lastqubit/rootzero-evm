// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {Blocks, Cursors, Keys} from "../Codec.sol";
import {Position} from "../core/Types.sol";
import {OutOfBounds} from "../utils/Errors.sol";

/// @dev Complete consumers: old code retains absolute positions; new code passes cursors.
/// Measurement includes decoding, required bounds checks and advancement, but excludes
/// source setup and the single final conversion needed to compare stream state.
contract CursorConsumerEnvelopeOld {
    function balances(uint abs, uint endAbs) private pure returns (uint sum, uint count) {
        while (abs < endAbs) {
            (bytes32 asset, uint amount) = LegacyBlocks.unpackBalance(abs);
            unchecked { abs += 72; }
            if (abs > endAbs) revert OutOfBounds();
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint abs = uint32(cur);
        uint endAbs = uint32(cur >> 32);
        uint beforeGas = gasleft();
        while (abs < endAbs) {
            (uint body, uint next) = LegacyBlocks.enter(abs, Keys.Bytes);
            if (next > endAbs) revert OutOfBounds();
            (uint value, uint children) = balances(body, next);
            abs = next;
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = (cur & ~uint(type(uint32).max)) | abs;
    }
}

contract CursorConsumerEnvelopeNew {
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
            uint blockCur;
            (blockCur, cur) = Blocks.take(cur, Keys.Bytes);
            uint payloadCur;
            unchecked { payloadCur = blockCur + 8; }
            (uint value, uint children) = balances(payloadCur);
            unchecked { sum += value; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerStepOld {
    function balances(uint abs, uint endAbs) private pure returns (uint sum, uint count) {
        while (abs < endAbs) {
            (bytes32 asset, uint amount) = LegacyBlocks.unpackBalance(abs);
            unchecked { abs += 72; }
            if (abs > endAbs) revert OutOfBounds();
            unchecked { sum += uint(asset) + amount; ++count; }
        }
    }
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        uint abs = uint32(cur);
        uint endAbs = uint32(cur >> 32);
        uint beforeGas = gasleft();
        while (abs < endAbs) {
            (uint cmd, uint value, bytes calldata input, uint next) = LegacyBlocks.unpackStep(abs);
            if (next > endAbs) revert OutOfBounds();
            uint inputAbs;
            assembly ("memory-safe") { inputAbs := input.offset }
            (uint childSum, uint children) = balances(inputAbs, inputAbs + input.length);
            abs = next;
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = (cur & ~uint(type(uint32).max)) | abs;
    }
}

contract CursorConsumerStepNew {
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
            uint cmd; uint value; uint inputCur;
            (cmd, value, inputCur, cur) = Blocks.unpackStep(cur);
            (uint childSum, uint children) = balances(inputCur);
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainOld {
    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint count, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32) | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(uint(1)), 7, bytes32(uint(2)), 3, bytes32(0));
        uint abs = uint32(cur);
        uint endAbs = uint32(cur >> 32);
        uint beforeGas = gasleft();
        while (abs < endAbs) {
            (bytes32 asset, uint amount) = LegacyBlocks.unpackBalance(abs);
            unchecked { abs += 72; }
            if (abs > endAbs) revert OutOfBounds();
            uint next;
            unchecked { next = abs + 136; }
            if (next > endAbs) revert OutOfBounds();
            LegacyBlocks.expectPositionConstraints(abs, position);
            abs = next;
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = (cur & ~uint(type(uint32).max)) | abs;
    }
}

contract CursorConsumerChainNew {
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
