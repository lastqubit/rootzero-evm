// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";
import {Blocks, Cursors, Keys} from "../Codec.sol";
import {Position} from "../core/Types.sol";
import {OutOfBounds} from "../utils/Errors.sol";

import {CursorAbsoluteWrappers} from "./CursorAbsoluteWrappers.sol";
import {CursorNextBalanceHarness, CursorNextStepHarness} from "./TestCursorNext.sol";
contract CursorConsumerEnvelopeAbsBalance {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorAbsoluteWrappers.unpackBalance(cur);
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

contract CursorConsumerEnvelopeAbsFixed {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorAbsoluteWrappers.unpackBalance(cur);
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

contract CursorConsumerEnvelopeAbsAll {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorAbsoluteWrappers.unpackBalance(cur);
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
            uint blockCur = CursorAbsoluteWrappers.take(cur, Keys.Bytes);
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

contract CursorConsumerStepAbsBalance {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorAbsoluteWrappers.unpackBalance(cur);
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

contract CursorConsumerStepAbsFixed {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorAbsoluteWrappers.unpackBalance(cur);
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

contract CursorConsumerStepAbsAll {
    function balances(uint cur) private pure returns (uint sum, uint count) {
        while (uint32(cur) < uint32(cur >> 32)) {
            bytes32 asset; uint amount;
            (asset, amount, cur) = CursorAbsoluteWrappers.unpackBalance(cur);
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
            (cmd, value, inputCur, cur) = CursorAbsoluteWrappers.unpackStep(cur);
            (uint childSum, uint children) = balances(inputCur);
            unchecked { sum += cmd + value + childSum; count += children; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainAbsBalance {
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
            (asset, amount, cur) = CursorAbsoluteWrappers.unpackBalance(cur);
            cur = Blocks.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainAbsFixed {
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
            (asset, amount, cur) = CursorAbsoluteWrappers.unpackBalance(cur);
            cur = CursorAbsoluteWrappers.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorConsumerChainAbsAll {
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
            (asset, amount, cur) = CursorAbsoluteWrappers.unpackBalance(cur);
            cur = CursorAbsoluteWrappers.expectPositionConstraints(cur, position);
            unchecked { sum += uint(asset) + amount; ++count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorNextBalanceAbsolute is CursorNextBalanceHarness {
    function decode(uint cur) internal pure override returns (bytes32, uint, uint) {
        return CursorAbsoluteWrappers.unpackBalance(cur);
    }
}
contract CursorNextStepAbsolute is CursorNextStepHarness {
    function decode(uint cur) internal pure override returns (uint, uint, uint, uint) {
        return CursorAbsoluteWrappers.unpackStep(cur);
    }
}
