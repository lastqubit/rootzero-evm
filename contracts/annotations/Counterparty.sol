// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AnnotationEvent} from "../events/Annotation.sol";
import {Blocks} from "../codec/Blocks.sol";

/// @title CounterpartyAnnot
/// @notice Associates an entity with an account as counterparty.
/// @dev The latest trusted annotation replaces the earlier value. Zero identifies
/// Rootzero. Consumers validate the claim; an annotation grants no authority.
abstract contract CounterpartyAnnot is AnnotationEvent {
    /// @notice Attach a counterparty account to `entity`.
    /// @param entity Entity receiving the annotation.
    /// @param account Counterparty account ID, or zero for Rootzero.
    function annotateCounterparty(uint entity, bytes32 account) internal virtual {
        emit Annotation(entity, Blocks.createCounterparty(account));
    }
}
