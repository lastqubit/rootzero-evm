// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AnnotationEvent} from "../events/Annotation.sol";
import {Blocks} from "../codec/Blocks.sol";

/// @title ActionAnnot
/// @notice Emits a primary semantic action annotation for an entity.
/// @dev For a trusted emitter, the latest action replaces the earlier value.
abstract contract ActionAnnot is AnnotationEvent {
    /// @notice Attach a primary semantic action to `entity`.
    /// @param entity Entity receiving the action annotation.
    /// @param value Canonical action identifier, such as a value from `Actions`.
    function annotateAction(uint entity, uint value) internal virtual {
        emit Annotation(entity, Blocks.createAction(value));
    }
}
