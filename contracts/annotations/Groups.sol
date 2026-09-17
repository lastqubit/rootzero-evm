// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AnnotationEvent} from "../events/Annotation.sol";
import {Blocks} from "../codec/Blocks.sol";

/// @title GroupsAnnot
/// @notice Describes grouped endpoint lanes using off-chain role hints.
/// @dev The latest trusted annotation replaces the previous description; empty clears it.
/// Syntax is interpreted offchain and never changes decoding or allocation.
abstract contract GroupsAnnot is AnnotationEvent {
    /// @notice Describe only the lanes grouped by an endpoint's loop.
    /// @param endpoint Endpoint ID receiving the annotation.
    /// @param description Comma-separated lane alias lists, e.g. "#state as (debit, credit)".
    /// Only #state, #input, and #output are lane references in this annotation.
    /// Omitted lanes have no grouping hint; descriptor schemas take precedence over hints.
    function annotateGroups(uint endpoint, string memory description) internal virtual {
        emit Annotation(endpoint, Blocks.createGroups(description));
    }
}
