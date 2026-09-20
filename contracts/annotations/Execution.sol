// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AnnotationEvent} from "../events/Annotation.sol";
import {Blocks} from "../codec/Blocks.sol";

/// @title ExecutionCost
/// @notice Publishes a command execution estimate in destination-local execution units.
/// @dev Estimated cost is base + batch * batchCount. A batch is one logical group
/// processed by the command, including all constituent blocks of grouped inputs.
/// The latest trusted annotation replaces the previous estimate. Missing metadata
/// means unknown cost; zero values are valid estimates, not a clearing sentinel.
/// Estimates are advisory and exclude pipeline and transport overhead.
abstract contract ExecutionCost is AnnotationEvent {
    /// @notice Attach an execution cost estimate to a command.
    /// @param entity Command ID receiving the annotation.
    /// @param base Fixed execution cost per invocation.
    /// @param batch Additional execution cost per logical batch.
    function executionCost(uint entity, uint base, uint batch) internal virtual {
        emit Annotation(entity, Blocks.createExecutionCost(base, batch));
    }
}
