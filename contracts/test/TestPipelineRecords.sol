// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Logs} from "../codec/Logs.sol";
import {Cursors} from "../utils/Cursors.sol";

/// @notice Direct access to the pipeline Step and State encoders.
contract TestPipelineRecords {
    function step(uint index, uint value, bytes calldata input, bool withInput) external {
        Logs.step(index, value, Cursors.wrap(input), withInput);
    }

    /// @dev Returns the stream after logging to prove its length word is restored.
    function state(bytes memory stream, uint index) external returns (bytes memory) {
        Logs.state(stream, index);
        return stream;
    }

    /// @dev Logs the shared empty bytes value and reports the zero slot afterwards.
    function emptyState(uint index) external returns (uint zeroSlot, uint freePointer) {
        bytes memory empty;
        assembly ("memory-safe") { freePointer := mload(0x40) }
        Logs.state(empty, index);
        assembly ("memory-safe") {
            zeroSlot := mload(0x60)
            freePointer := sub(mload(0x40), freePointer)
        }
    }
}
