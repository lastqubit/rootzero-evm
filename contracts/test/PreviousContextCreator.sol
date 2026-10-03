// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Encoder} from "../codec/Encoder.sol";
import {Keys} from "../codec/Keys.sol";

/// @dev Historical complete-child creator, retained only for benchmark comparisons.
/// Production creators now always accept payloads and construct child headers.
library PreviousContextCreator {
    /// @notice Create a CONTEXT by copying complete memory-backed STATE and INPUT children.
    /// @dev Sources must each contain exactly one validated BYTES block, including
    /// its header. Copies children intact without repeating validation. Checks the
    /// complete result size fits uint32 and allocates only the final result.
    function createContext(
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure returns (bytes memory value) {
        uint stateSize = state.length;
        uint inputSize = input.length;
        uint size = 40 + stateSize + inputSize;
        value = Encoder.allocate(size);
        uint abs = Encoder.pos(value, 0);
        unchecked {
            abs = Encoder.writeHeader(abs, Keys.Context, size - 8);
            abs = Encoder.write32(abs, account);
            abs = Encoder.copy(abs, state, stateSize);
            Encoder.copy(abs, input, inputSize);
        }
    }

    /// @notice Create a CONTEXT by copying complete calldata-backed STATE and INPUT children.
    /// @dev Both cursors must satisfy current <= end <= calldatasize and select
    /// exactly one validated BYTES block including its header. Ignores metadata,
    /// preserves cursors, and performs no repeated header/bounds checks. Checks
    /// the complete result size fits uint32; copies directly to the final result.
    /// @param stateCur Cursor over one complete STATE block, including its header.
    /// @param inputCur Cursor over one complete INPUT block, including its header.
    function createContext(bytes32 account, uint stateCur, uint inputCur) internal pure returns (bytes memory value) {
        uint stateSize = Encoder.length(stateCur);
        uint inputSize = Encoder.length(inputCur);
        uint size = 40 + stateSize + inputSize;
        value = Encoder.allocate(size);
        uint abs = Encoder.pos(value, 0);
        unchecked {
            abs = Encoder.writeHeader(abs, Keys.Context, size - 8);
            abs = Encoder.write32(abs, account);
            abs = Encoder.copy(abs, uint32(stateCur), stateSize);
            Encoder.copy(abs, uint32(inputCur), inputSize);
        }
    }

}
