// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Encoder} from "../codec/Encoder.sol";
// Frozen creator for historical codec benchmarks.
library PreviousExecutionCost {
    /// @notice Create an EXECUTION_COST annotation with base and per-batch costs.
    /// @param base Fixed execution cost per invocation.
    /// @param batch Additional execution cost per logical batch.
    /// @return value Complete encoded annotation with zero allocation padding.
    function createExecutionCost(uint base, uint batch) internal pure returns (bytes memory value) {
        value = Encoder.allocate(72);
        uint abs = Encoder.writeHeader(Encoder.pos(value, 0), bytes4(keccak256("#executionCost")), 64);
        abs = Encoder.write32(abs, bytes32(base));
        Encoder.write32(abs, bytes32(batch));
    }

}
