// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

// Event system (LOG0, no topics):
// - Every record starts with one category byte. Headers are NOT block headers.
// - Integers and IDs below are full 32-byte big-endian words unless marked :1.
// - Category values define stable layouts. Incompatible layouts get new values;
//   unknown categories must be preserved or skipped, never guessed from payloads.
// - Category 0 is reserved. Standard blocks use [key:4][payload length:4][payload].
//
// Category         Wire layout                                             Size
// 0x01 Access       [category:1][node][enabled:1]                            34
// 0x02 Introduction [category:1][peer][origin][claimed block number][name...] 97 + name
// 0x03 Metadata     [category:1][subject][blocks...]                         33 + blocks
// 0x04 Execution    [category:1][endpoint][account][STATE?][INPUT?][OUTPUT?] 65 + blocks
// 0x05 Endpoint     [category:1][endpoint][state][input][output][name...]    129 + name
// 0x06 Reserved     Former Pipeline category; never reuse.
// 0x07 Balance      [category:1][account][asset][actual balance]             97
// 0x08 Envelope     [category:1][portal][resources][key][digest]             129
// 0x09 Resolution   [category:1][key][digest][resolved:1]                    66
//
// Names are trailing raw UTF-8 bytes (no block header, length word or padding).
// Host names are optional discovery hints supplied by introductions; endpoint
// names describe registration. IDs remain the identifiers; names are not unique.
// Hosts without introductions are identified by host ID without a naming event.
// Additional labels and display overrides belong offchain.
//
// Execution:
// - Commands use the context account; guards use Accounts.toUser(msg.sender)
//   after authorization. Ports default to zero, with explicit attribution allowed.
// - Selected containers retain their standard headers, including empty lanes.
// - One completion record per logged invocation; hook/nested records precede it.
// - The event and returned output share a buffer. Emit before exposing output.
// - Resolve schemas through Endpoint registration, scoped by chain, emitter and
//   endpoint ID; custom operation meaning is interpreted offchain.
//
// Endpoint identity flags (byte at bits 224..231 of the endpoint ID):
// - Bit 0 Funded, bit 1 Admin, bit 2 log Execution, bits 3/4/5 log State/Input/Output,
//   bit 6 endpoint-defined, bit 7 Handoff. Logging is part of endpoint identity.
// - Logs.Execution=4, State=12, Input=20, Output=36. Lane flags include Execution.
// - Combine logging and behavior flags at registration, e.g. Logs.Input | Flags.Admin.
// - With no logging bits, no record or buffer preparation is requested. Lane bits
//   without Execution are invalid. Specs contain no flags; Endpoint has no flag field.
// - Endpoint IDs and logging policy are fixed at deployment.
// - Execution is both category 4 and the execution logging flag; other categories
//   are identifiers only and must not be combined as flags.
//
// Offchain interpretation:
// - Events record identities, typed values and category-defined facts. Endpoint
//   flags only select lanes; neither Endpoint nor Envelope carries semantic codes.
// - Tags, action classifications and custom state projections belong in an
//   offchain registry keyed by chain and endpoint, versioned by applicable blocks.
// - Indexers retain raw events and endpoint schemas so interpretations can change
//   and projections can be rebuilt. Unknown endpoints remain readable typed data.
// - Raw invocation values alone do not prove custom effects; the registry must
//   describe the guarantees of the endpoint implementation. Core categories such
//   as Access and Balance retain their defined onchain state meanings.
//
// Other categories:
// - Access records explicit node authorization changes owned by the emitter.
//   enabled is exactly 0 or 1. Guardians and account permissions are excluded.
// - Balance identity is (host, account, asset), with host derived from chain and
//   emitter address. The same account/asset on different hosts has independent
//   balances. Each record replaces only that compound identity's balance; no delta.
// - Metadata's subject is what is described, not necessarily the emitter. Its
//   blocks may include SCHEMA, LANE or COUNTERPARTY. No wrapper
//   or codes are needed. Multiple blocks can describe one subject in one record.
// - Introduction is a provenance claim, not authorization or verified creation.
// - Envelope contains portal, resources, key and digest; interpretation is offchain.
// - Resolution ends in exactly 0 (unresolved) or 1 (resolved), not a code word.
// - Reverts discard all records. Identity and trust come from the emitting
//   contract and chain; these helpers do not authorize or mutate application state.

import {Encoder} from "./Encoder.sol";

/// @notice Category-specific event encoders. Scalar helpers use temporary memory.
library Logs {
    // Stable event wire categories; zero is reserved.
    uint internal constant Access = 1;
    uint internal constant Introduction = 2;
    uint internal constant Metadata = 3;
    uint internal constant Execution = 4;
    uint internal constant Endpoint = 5;
    uint internal constant Balance = 7;
    uint internal constant Envelope = 8;
    uint internal constant Resolution = 9;

    /// @dev Logging flags only. Lane constants include Execution; zero disables logging.
    uint internal constant State = Execution | (1 << 3);
    uint internal constant Input = Execution | (1 << 4);
    uint internal constant Output = Execution | (1 << 5);

    /// @notice Record a node authorization change; accounts are not subjects.
    function access(uint node, bool enabled) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore8(start, Access)
            mstore(add(start, 1), node)
            mstore8(add(start, 33), iszero(iszero(enabled)))
            log0(start, 34)
        }
    }

    /// @notice Emit a prepared execution buffer without copying.
    /// @dev Caller owns [abs, abs+size), size >= 65, with account at abs+33 and
    /// complete selected containers after abs+65. Consumes category/endpoint slots.
    function execution(uint id, uint abs, uint size) internal {
        assembly ("memory-safe") {
            mstore8(abs, Execution)
            mstore(add(abs, 1), id)
            log0(abs, size)
        }
    }

    /// @notice Emit one memory-backed execution lane using temporary memory.
    function execution(uint id, bytes32 account, bytes4 key, bytes memory value) internal {
        uint start;
        assembly ("memory-safe") { start := mload(0x40) }
        Encoder.write32(start + 33, account);
        Encoder.wrap(start + 65, key, value);
        execution(id, start, 73 + value.length);
    }

    /// @notice Emit one validated calldata-backed execution lane.
    function execution(uint id, bytes32 account, bytes4 key, uint cur) internal {
        uint start;
        assembly ("memory-safe") { start := mload(0x40) }
        Encoder.write32(start + 33, account);
        Encoder.wrap(start + 65, key, cur);
        execution(id, start, 73 + Encoder.length(cur));
    }

    /// @notice Publish an endpoint identity, packed lanes and its registration name.
    function endpoint(uint id, uint state, uint input, uint output, string memory name) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore8(start, Endpoint)
            mstore(add(start, 1), id)
            mstore(add(start, 33), state)
            mstore(add(start, 65), input)
            mstore(add(start, 97), output)
            let size := mload(name)
            mcopy(add(start, 129), add(name, 32), size)
            log0(start, add(129, size))
        }
    }

    /// @notice Emit actual updated balance; call after a successful mutation.
    function balance(bytes32 account, bytes32 asset, uint amount) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore8(start, Balance)
            mstore(add(start, 1), account)
            mstore(add(start, 33), asset)
            mstore(add(start, 65), amount)
            log0(start, 97)
        }
    }

    /// @notice Publish metadata blocks about one subject, preserving their bytes.
    /// @dev Accepts ordinary bytes including shared empty values; uses temporary
    /// memory without advancing the allocator or modifying the source.
    function metadata(uint subject, bytes memory data) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            let size := mload(data)
            mstore8(start, Metadata)
            mstore(add(start, 1), subject)
            mcopy(add(start, 33), add(data, 32), size)
            log0(start, add(33, size))
        }
    }

    /// @notice Publish peer provenance; blocknum is a caller-supplied claim.
    function introduction(uint peer, bytes32 originAccount, uint blocknum, string memory name) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore8(start, Introduction)
            mstore(add(start, 1), peer)
            mstore(add(start, 33), originAccount)
            mstore(add(start, 65), blocknum)
            let size := mload(name)
            mcopy(add(start, 97), add(name, 32), size)
            log0(start, add(97, size))
        }
    }

    /// @notice Describe a transport operation without semantic codes.
    function envelope(uint portal, uint resources, bytes32 key, bytes32 digest) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore8(start, Envelope)
            mstore(add(start, 1), portal)
            mstore(add(start, 33), resources)
            mstore(add(start, 65), key)
            mstore(add(start, 97), digest)
            log0(start, 129)
        }
    }

    /// @notice Record a message becoming unresolved (false) or resolved (true).
    function resolution(bytes32 key, bytes32 digest, bool resolved) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore8(start, Resolution)
            mstore(add(start, 1), key)
            mstore(add(start, 33), digest)
            mstore8(add(start, 65), iszero(iszero(resolved)))
            log0(start, 66)
        }
    }
}
