// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

// Event system (LOG0, no topics):
// - Every record starts with one category byte. Headers are NOT block headers.
// - Integers and IDs below are full 32-byte big-endian words unless marked :1.
// - Category values define stable layouts. Incompatible layouts get new values;
//   unknown categories must be preserved or skipped, never guessed from payloads.
// - Category 0 and every unassigned value are reserved. Standard blocks use
//   [key:4][payload length:4][payload].
// - Pipeline, State, Input, Output and Value are also endpoint-ID flag bits; the
//   other categories are numbered after them.
//
// Category         Wire layout                                             Size
// 0x04 Pipeline     [category:1][account][command...]                        33 + 32n
// 0x08 State        [category:1][index:1][state payload]                     2 + state
// 0x10 Input        Step: [category:1][index:1][value?][input payload?]      2 + value + input
// 0x20 Output       Reserved; a step's output is recorded as the next State.
// 0x40 Value        Reserved; also the Step index bit marking a value word.
// 0x41 Access       [category:1][node][enabled:1]                            34
// 0x42 Introduction [category:1][peer][origin][claimed block number][name...] 97 + name
// 0x43 Metadata     [category:1][subject][blocks...]                         33 + blocks
// 0x44 Endpoint     [category:1][endpoint][state][input][output][name...]    129 + name
// 0x45 Balance      [category:1][account][asset][actual balance]             97
// 0x46 Envelope     [category:1][portal][resources][key][digest]             129
// 0x47 Resolution   [category:1][key][digest][resolved:1]                    66
//
// Names are trailing raw UTF-8 bytes (no block header, length word or padding).
// Host names are optional discovery hints supplied by introductions; endpoint
// names describe registration. IDs remain the identifiers; names are not unique.
// Hosts without introductions are identified by host ID without a naming event.
// Additional labels and display overrides belong offchain.
//
// Pipeline records:
// - Endpoints never log their own execution; callers do. The protocol Pipeline
//   emits one Pipeline record, then for each step i an optional State and an
//   optional Step, before the step runs. Records emitted by the step's hooks follow.
// - The Pipeline record lists the account and every step's command ID through the
//   first handoff; the continuation belongs to the destination host. Its length
//   gives the step count, (size - 33) / 32. A pipeline has at most 64 steps.
// - Step i is emitted when its command carries the Input hint or the pipeline
//   assigns it a nonzero native value. Index bit 6 (Value) marks a following 32-byte
//   value, in wei, as assigned by the pipeline. The input payload follows when the
//   command carries the Input hint; it excludes the INPUT block header.
// - State i is the state block stream passed to step i, without its STATE header.
//   It is emitted once when step i carries the State hint or step i - 1 carries
//   the Output hint. The final state is always empty and never emitted.
// - Records pair by emitter, Pipeline record and step index. Pipelines on one
//   emitter do not nest; each Pipeline record ends that emitter's previous one.
// - Resolve schemas through Endpoint registration, scoped by chain, emitter and
//   endpoint ID; custom operation meaning is interpreted offchain.
//
// Endpoint identity flags (byte at bits 224..231 of the endpoint ID):
// - Bit 0 Funded, bit 1 Admin, bit 2 Pipeline, bits 3/4/5 State/Input/Output
//   logging hints, bit 6 Value, bit 7 Handoff. As flags, Pipeline and Value are
//   reserved potential hints with no current meaning.
// - Logging hints tell callers which lanes are worth recording; they are not
//   rules, and endpoints ignore them. Logs.State=8, Input=16, Output=32.
// - Combine hints and behavior flags at registration, e.g. Logs.Input | Flags.Admin.
//   Hints are part of endpoint identity and fixed at deployment.
//
// Offchain interpretation:
// - Events record identities, typed values and category-defined facts. Endpoint
//   flags only hint lanes; neither Endpoint nor Envelope carries semantic codes.
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

/// @title Logs
/// @notice Category-specific event encoders. Scalar helpers use temporary memory.
library Logs {
    // Endpoint-ID flag bits that double as record categories.
    /// @dev Pipeline record category; flag bit 2, a reserved potential hint.
    uint internal constant Pipeline = 1 << 2;
    /// @dev State record category; flag bit 3, the STATE lane logging hint.
    uint internal constant State = 1 << 3;
    /// @dev Step record category; flag bit 4, the INPUT lane logging hint.
    uint internal constant Input = 1 << 4;
    /// @dev Reserved category; flag bit 5, the OUTPUT lane logging hint.
    uint internal constant Output = 1 << 5;
    /// @dev Reserved category; flag bit 6, a reserved potential hint. In a Step
    /// record's index byte, marks a following assigned-value word.
    uint internal constant Value = 1 << 6;

    // Record categories only, numbered after the flag bits.
    /// @dev Access record category.
    uint internal constant Access = 65;
    /// @dev Introduction record category.
    uint internal constant Introduction = 66;
    /// @dev Metadata record category.
    uint internal constant Metadata = 67;
    /// @dev Endpoint record category.
    uint internal constant Endpoint = 68;
    /// @dev Balance record category.
    uint internal constant Balance = 69;
    /// @dev Envelope record category.
    uint internal constant Envelope = 70;
    /// @dev Resolution record category.
    uint internal constant Resolution = 71;

    /// @notice Record a node authorization change; accounts are not subjects.
    /// @param node Node identifier.
    /// @param enabled Whether authorization is enabled.
    function access(uint node, bool enabled) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore8(start, Access)
            mstore(add(start, 1), node)
            mstore8(add(start, 33), iszero(iszero(enabled)))
            log0(start, 34)
        }
    }

    /// @notice Record one pipeline step's assigned native value and hinted input.
    /// @dev Uses temporary memory. Requires index < 64, leaving bit 6 for Value;
    /// Pipeline enforces its step limit. A zero value emits no value word.
    /// @param index Zero-based step index within the pipeline.
    /// @param value Native value assigned to the step, in wei.
    /// @param inputCur Bounded calldata cursor over the step's input payload.
    /// @param withInput Whether to append the input payload.
    function step(uint index, uint value, uint inputCur, bool withInput) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore8(start, Input)
            let abs := add(start, 2)
            switch iszero(value)
            case 1 {
                mstore8(add(start, 1), index)
            }
            default {
                mstore8(add(start, 1), or(index, Value))
                mstore(abs, value)
                abs := add(abs, 32)
            }
            if withInput {
                let source := and(inputCur, 0xffffffff)
                let size := sub(and(shr(32, inputCur), 0xffffffff), source)
                calldatacopy(abs, source, size)
                abs := add(abs, size)
            }
            log0(start, sub(abs, start))
        }
    }

    /// @notice Record the state block stream passed to one pipeline step.
    /// @dev Writes the category and index over the last two bytes of the length
    /// word, emits in place without copying, then restores the length. Accepts the
    /// shared empty bytes value. Requires index < 64.
    /// @param stream State block stream passed to the step.
    /// @param index Zero-based step index within the pipeline.
    function state(bytes memory stream, uint index) internal {
        assembly ("memory-safe") {
            let size := mload(stream)
            let data := add(stream, 32)
            mstore8(sub(data, 2), State)
            mstore8(sub(data, 1), index)
            log0(sub(data, 2), add(size, 2))
            mstore(stream, size)
        }
    }

    /// @notice Publish an endpoint identity, packed lanes and its registration name.
    /// @param id Registered endpoint node identifier.
    /// @param stateSpec State block specification or named lane.
    /// @param inputSpec Input block specification or named lane.
    /// @param outputSpec Output block specification or named lane.
    /// @param name Endpoint registration name.
    function endpoint(uint id, uint stateSpec, uint inputSpec, uint outputSpec, string memory name) internal {
        assembly ("memory-safe") {
            let start := mload(0x40)
            mstore8(start, Endpoint)
            mstore(add(start, 1), id)
            mstore(add(start, 33), stateSpec)
            mstore(add(start, 65), inputSpec)
            mstore(add(start, 97), outputSpec)
            let size := mload(name)
            mcopy(add(start, 129), add(name, 32), size)
            log0(start, add(129, size))
        }
    }

    /// @notice Emit actual updated balance; call after a successful mutation.
    /// @param account Account identifier.
    /// @param asset Asset identifier.
    /// @param amount Quantity in the asset's native units.
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
    /// @param subject Identifier of the entity described by the metadata.
    /// @param data Complete metadata block stream.
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
    /// @param peer Peer host node identifier.
    /// @param originAccount Transaction-origin account identifier.
    /// @param blocknum Caller-supplied block-number claim.
    /// @param name Self-declared host discovery name.
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
    /// @param portal Transport portal node identifier.
    /// @param resources Transport resource descriptor.
    /// @param key Forwarding or recovery lookup key.
    /// @param digest Message digest.
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
    /// @param key Forwarding or recovery lookup key.
    /// @param digest Message digest.
    /// @param resolved Whether the message is resolved.
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
