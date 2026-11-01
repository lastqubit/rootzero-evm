// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Logs} from "../codec/Logs.sol";
import {Cursors} from "../utils/Cursors.sol";

/// @notice Direct access to the pipeline step logger.
contract TestPipelineRecords {
    /// @dev Returns the stream after logging to prove its length word is restored.
    function step(uint index, uint cmd, uint prevCmd, bytes memory stream, uint value, bytes calldata input)
        external
        returns (bytes memory)
    {
        Logs.step(index, cmd, prevCmd, stream, value, Cursors.wrap(input));
        return stream;
    }

    /// @dev Logs the shared empty bytes value and reports the zero slot afterwards.
    function emptyState(uint index) external returns (uint zeroSlot, uint freePointer) {
        bytes memory empty;
        assembly ("memory-safe") { freePointer := mload(0x40) }
        Logs.step(index, uint(Logs.State) << 224, 0, empty, 0, 0);
        assembly ("memory-safe") {
            zeroSlot := mload(0x60)
            freePointer := sub(mload(0x40), freePointer)
        }
    }
}
