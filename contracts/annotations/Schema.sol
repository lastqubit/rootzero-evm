// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Encoder} from "../codec/Encoder.sol";
import {Specs} from "../codec/Specs.sol";
import {Logs} from "../codec/Logs.sol";
import {Runtime} from "../core/Runtime.sol";

/// @title SchemaAnnot
/// @notice Emits block-schema and lane annotations for the current host.
/// @dev Schema annotations accumulate for distinct block keys. For a trusted
/// emitter, the latest schema for the same block key replaces the earlier claim.
/// Bodies may start with `name:`. Without it, standard keys use their canonical
/// alias and nonstandard keys remain unnamed. The DSL is interpreted offchain.
abstract contract SchemaAnnot is Runtime {
    /// @notice Publish a lane using the first four bytes of the key string's hash.
    /// @dev Hashes the exact string bytes; adds no prefix and performs no normalization.
    function lane(string memory body, string memory key, uint spec) internal returns (uint) {
        return lane(body, uint32(bytes4(keccak256(bytes(key)))), spec);
    }

    /// @notice Publish a lane description and attach its host-local key to a block spec.
    /// @dev The body is interpreted offchain. All references must use the embedded
    /// block type; mixed types require a parent block. Zero denotes an unnamed lane.
    /// Lane metadata is keyed by host and lane key, independently of block schemas.
    /// @param body Schema expression describing one group of consecutive blocks.
    /// @param key Nonzero host-local lane identifier; never a wire block key.
    /// @param spec Plain block spec, retaining its existing bounds and allocation hint.
    /// @return value Packed block spec with the lane key in its lowest 32 bits.
    function lane(string memory body, uint32 key, uint spec) internal returns (uint value) {
        value = Specs.toLane(spec, key);
        Logs.metadata(host, Encoder.createLane(value, bytes(body)));
    }

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

    /// @notice Publish a ranged block spec using the first four bytes of the key string's hash.
    /// @dev Hashes the exact string bytes, independently of any name prefix in body.
    function schema(
        string memory body,
        string memory key,
        uint32 min,
        uint32 max,
        uint32 hint
    ) internal returns (uint) {
        return schema(body, uint32(bytes4(keccak256(bytes(key)))), min, max, hint);
    }

    /// @notice Construct and publish an exact-size context-local block specification.
    /// @param body Schema DSL string, optionally prefixed with `name:`.
    /// @param key Context-local key value.
    /// @param size Exact payload length and initial per-block payload capacity.
    /// @return spec The context-local block specification.
    function schema(string memory body, uint32 key, uint32 size) internal returns (uint spec) {
        return schema(body, Specs.create(key, size));
    }

    /// @notice Publish an exact-size block spec using the first four bytes of the key string's hash.
    /// @dev Hashes the exact string bytes, independently of any name prefix in body.
    function schema(string memory body, string memory key, uint32 size) internal returns (uint) {
        return schema(body, uint32(bytes4(keccak256(bytes(key)))), size);
    }

    /// @notice Publish an already constructed block specification for the current host.
    /// @param body Schema DSL string, optionally prefixed with `name:`.
    /// @param spec Packed block specification.
    /// @return The published block specification.
    function schema(string memory body, uint spec) internal returns (uint) {
        Logs.metadata(host, Encoder.createSchema(spec, bytes(body)));
        return spec;
    }
}
