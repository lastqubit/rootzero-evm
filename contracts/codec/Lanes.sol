// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {ValueOverflow} from "../utils/Errors.sol";

/// @notice Endpoint lane metadata: a block spec and four uint32 code slots.
/// @dev Layout: [spec:16][codes:16]. A plain Specs constant is a silent lane.
/// Nonzero codes enable logging, including for an empty stream. Extract the
/// spec before passing a lane to APIs that expect a block specification.
library Lanes {
    uint private constant CodesMask = type(uint128).max;

    /// @notice Combine a specification with codes without truncation or overlap.
    /// @dev The specification must have its lower 128 bits clear.
    function create(uint specification, uint value) internal pure returns (uint) {
        if ((specification & CodesMask) != 0 || value > CodesMask) revert ValueOverflow();
        return specification | value;
    }

    function spec(uint lane) internal pure returns (uint) {
        return lane & ~CodesMask;
    }

    function codes(uint lane) internal pure returns (uint) {
        return lane & CodesMask;
    }
}
