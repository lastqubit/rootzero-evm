// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Blocks} from "../codec/Blocks.sol";
import {Headers} from "../codec/Headers.sol";
import {Position} from "../core/Types.sol";

abstract contract CursorDeferredConstraintHarness {
    function check(uint cur, Position memory position) internal pure virtual;
    function save(uint cur) internal pure virtual returns (uint selected) {
        (selected, ) = Blocks.takeFixed(cur, Headers.PositionConstraints);
    }
    function measure(bytes calldata source, uint[] calldata offsets, uint[] calldata lengths, Position memory position, bool includeSetup)
        external view returns (uint gasUsed, uint count)
    {
        require(offsets.length == lengths.length);
        uint base;
        assembly ("memory-safe") { base := source.offset }
        uint beforeGas = gasleft();
        uint[] memory cursors = new uint[](offsets.length);
        for (uint i; i < offsets.length; ++i) {
            require(offsets[i] <= source.length && lengths[i] <= source.length - offsets[i]);
            uint abs = base + offsets[i];
            uint cur = abs | ((abs + lengths[i]) << 32);
            // A custom unpacker saves only ranges that passed the exact header and bounds checks.
            cursors[i] = save(cur);
        }
        if (!includeSetup) beforeGas = gasleft();
        for (uint i; i < cursors.length; ++i) check(cursors[i], position);
        gasUsed = beforeGas - gasleft();
        count = cursors.length;
    }
}
contract CursorDeferredConstraintCurrent is CursorDeferredConstraintHarness {
    function check(uint cur, Position memory position) internal pure override {
        Blocks.expectPositionConstraints(cur, position);
    }
}
contract CursorDeferredConstraintValues is CursorDeferredConstraintHarness {
    function save(uint cur) internal pure override returns (uint selected) {
        (selected, ) = Blocks.unpackFixed(cur, Headers.PositionConstraints);
    }
    function check(uint cur, Position memory position) internal pure override {
        Blocks.checkPositionConstraints(uint32(cur), position);
    }
}
