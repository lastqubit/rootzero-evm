// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks, Memory, Position} from "../Codec.sol";
import {Sizes} from "../codec/Specs.sol";
import {OutOfBounds} from "../utils/Errors.sol";

contract TestLimitedPosition {
    function unpack(bytes calldata state, uint stateOffset, bytes calldata input, uint inputOffset)
        external pure returns (Position memory)
    {
        // The low-level helper requires the caller to establish both bounds.
        if (stateOffset > state.length || state.length - stateOffset < Sizes.Position) revert OutOfBounds();
        if (inputOffset > input.length || input.length - inputOffset < Sizes.Limits) revert OutOfBounds();
        uint positionAbs;
        uint limitsAbs;
        assembly ("memory-safe") {
            positionAbs := add(state.offset, stateOffset)
            limitsAbs := add(input.offset, inputOffset)
        }
        return Blocks.unpackLimitedPosition(positionAbs, limitsAbs);
    }

    function unpackMemory(bytes memory state, uint stateOffset, bytes calldata input, uint inputOffset)
        public pure returns (Position memory)
    {
        if (stateOffset > state.length || state.length - stateOffset < Sizes.Position) revert OutOfBounds();
        if (inputOffset > input.length || input.length - inputOffset < Sizes.Limits) revert OutOfBounds();
        uint positionAbs;
        uint limitsAbs;
        assembly ("memory-safe") {
            positionAbs := add(add(state, 0x20), stateOffset)
            limitsAbs := add(input.offset, inputOffset)
        }
        return Memory.unpackLimitedPosition(positionAbs, limitsAbs);
    }

    function copyIndependence(bytes memory state, bytes calldata input)
        external pure returns (Position memory first, Position memory second, bytes memory source)
    {
        first = unpackMemory(state, 0, input, 0);
        second = unpackMemory(state, 0, input, 0);
        first.asset = bytes32(uint(1));
        first.amount = 2;
        first.liability = bytes32(uint(3));
        first.debt = 4;
        first.counterparty = bytes32(uint(5));
        assembly ("memory-safe") {
            // Mutate the source POSITION amount after creating both copies.
            mstore(add(state, 0x48), 999)
        }
        source = state;
    }
}
