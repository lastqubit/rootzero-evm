// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {Specs} from "../codec/Specs.sol";
import {AnnotationEvent} from "../events/Annotation.sol";
import {Runtime} from "../core/Runtime.sol";

/// @title SchemaAnnot
/// @notice Emits standard block-schema annotations for the current host.
/// @dev Schema annotations accumulate for distinct block keys. For a trusted
/// emitter, the latest schema for the same block key replaces the earlier claim.
/// Bodies may start with `name:`. Without it, standard keys use their canonical
/// alias and nonstandard keys remain unnamed. The DSL is interpreted offchain.
abstract contract SchemaAnnot is Runtime, AnnotationEvent {
    /// @notice Construct and publish a context-local block specification.
    /// @param body Schema DSL string, optionally prefixed with `name:`.
    /// @param key Context-local key value.
    /// @param min Minimum accepted payload length.
    /// @param max Maximum accepted payload length; zero means unbounded.
    /// @param hint Initial per-block payload capacity.
    /// @return spec The context-local block specification.
    function schema(
        string memory body,
        uint32 key,
        uint32 min,
        uint32 max,
        uint32 hint
    ) internal returns (uint spec) {
        return schema(body, Specs.create(key, min, max, hint));
    }

    /// @notice Construct and publish an exact-size context-local block specification.
    /// @param body Schema DSL string, optionally prefixed with `name:`.
    /// @param key Context-local key value.
    /// @param size Exact payload length and initial per-block payload capacity.
    /// @return spec The context-local block specification.
    function schema(string memory body, uint32 key, uint32 size) internal returns (uint spec) {
        return schema(body, Specs.create(key, size));
    }

    /// @notice Publish an already constructed block specification for the current host.
    /// @param body Schema DSL string, optionally prefixed with `name:`.
    /// @param spec Packed block specification.
    /// @return The published block specification.
    function schema(string memory body, uint spec) internal returns (uint) {
        emit Annotation(host, Blocks.createSchema(spec, body));
        return spec;
    }
}
