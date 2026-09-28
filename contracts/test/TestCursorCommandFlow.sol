// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {Blocks, Cursors} from "../Codec.sol";
import {Position} from "../core/Types.sol";
import {OutOfBounds} from "../utils/Errors.sol";

/// @dev Representative decode/dispatch workload, not a full host execution.
/// Both implementations keep packed cursors at every loop and helper boundary.
abstract contract CursorCommandFlow {
    function step(uint cur) internal pure virtual returns (uint, uint, uint, uint);
    function balance(uint cur) internal pure virtual returns (bytes32, uint, uint);
    function constraints(uint cur, Position memory position) internal pure virtual returns (uint);

    function command(uint cur, uint cmd, Position memory position)
        private pure returns (uint sum, uint records)
    {
        require(cmd == 1 || cmd == 2);
        while (uint32(cur) < uint32(cur >> 32)) {
            (position.asset, position.amount, cur) = balance(cur);
            cur = constraints(cur, position);
            bytes32 asset;
            uint amount;
            (asset, amount, cur) = balance(cur);
            // Use every decoded value and exercise two command branches.
            unchecked {
                sum += uint(position.asset) + uint(asset)
                    + (cmd == 1 ? position.amount + amount : position.amount * amount);
                ++records;
            }
        }
    }

    function measure(bytes calldata source, uint length, uint offset, uint metadata)
        external view returns (uint gasUsed, uint sum, uint records, uint finalCur, uint baseAbs)
    {
        require(offset <= length && length <= source.length);
        baseAbs = Cursors.base(source);
        uint cur = (baseAbs + offset) | ((baseAbs + length) << 32)
            | (metadata & ~uint(type(uint64).max));
        Position memory position = Position(bytes32(0), 0, bytes32(uint(2)), 3, bytes32(0));
        uint beforeGas = gasleft();
        while (uint32(cur) < uint32(cur >> 32)) {
            uint cmd;
            uint value;
            uint inputCur;
            (cmd, value, inputCur, cur) = step(cur);
            (uint result, uint count) = command(inputCur, cmd, position);
            unchecked { sum += result + value; records += count; }
        }
        gasUsed = beforeGas - gasleft();
        finalCur = cur;
    }
}

contract CursorCommandFlowNew is CursorCommandFlow {
    function step(uint cur) internal pure override returns (uint, uint, uint, uint) {
        return Blocks.unpackStep(cur);
    }
    function balance(uint cur) internal pure override returns (bytes32, uint, uint) {
        return Blocks.unpackBalance(cur);
    }
    function constraints(uint cur, Position memory position) internal pure override returns (uint) {
        return Blocks.expectPositionConstraints(cur, position);
    }
}

contract CursorCommandFlowOld is CursorCommandFlow {
    // Old LegacyBlocks delegates logical bounds and stream advancement to the caller.
    function advance(uint cur, uint abs) private pure returns (uint) {
        if (abs > uint32(cur >> 32)) revert OutOfBounds();
        return (cur & ~uint(type(uint32).max)) | abs;
    }
    function step(uint cur) internal pure override returns (uint cmd, uint value, uint inputCur, uint nextCur) {
        bytes calldata input;
        uint endAbs;
        (cmd, value, input, endAbs) = LegacyBlocks.unpackStep(uint32(cur));
        nextCur = advance(cur, endAbs);
        uint abs = Cursors.base(input);
        // The checked parent end bounds this child range.
        unchecked { inputCur = abs | ((abs + input.length) << 32); }
    }
    function balance(uint cur) internal pure override returns (bytes32 asset, uint amount, uint nextCur) {
        (asset, amount) = LegacyBlocks.unpackBalance(uint32(cur));
        unchecked { nextCur = advance(cur, uint(uint32(cur)) + 72); }
    }
    function constraints(uint cur, Position memory position) internal pure override returns (uint nextCur) {
        unchecked { nextCur = advance(cur, uint(uint32(cur)) + 136); }
        LegacyBlocks.expectPositionConstraints(uint32(cur), position);
    }
}
