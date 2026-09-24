// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

// Block stream:
// - encoding is [bytes4 key][bytes4 payloadLen][payload]
// - `payloadLen` is big-endian and covers only the block payload
// - payload layout is block-specific
//
// Schema:
// - schema strings accept an optional `name:` prefix before the payload body;
//   aliases otherwise come from the standard key catalog
// - payload schemas are `""` or a comma-separated item sequence; one optional
//   pair of outer braces may wrap a non-empty sequence without changing meaning
// - an empty schema string means the block has no structured payload
// - commas outside alias-list parentheses separate siblings at every level
// - `#x as (a, b)` expands to `#x as a, #x as b` in declaration order; it adds
//   no container or header and preserves the referenced key for every child
// - alias lists require at least two valid alias paths and an unmodified schema
//   reference; use expanded items with `maybe`, `many`, or `at` modifiers
// - empty entries, trailing commas, nested lists, and colliding alias paths are invalid
// - braces are presentation-only and do not change payload layout
// - command inputs are a single run when the input schema is non-empty
// - command state is a single active state run without trailing globals
// - run items may repeat at top level for batching
// - every declared child block header is present when its parent is non-empty
// - any block may use a zero-length payload as its empty form
// - `maybe #x` hints that the onchain consumer accepts the empty form of `#x`
//   when emptiness is not already intrinsic to the referenced block type
// - `many #x` alongside other items emits one generic list block containing
//   zero or more repeated `#x` items; the list header is always present
// - a custom schema consisting of exactly one `many #x` item uses its custom
//   key for the outer list block and contains repeated `#x` items directly,
//   whether or not the item is wrapped in braces
// - endpoint descriptor lanes identify their top-level block key directly
// - `portal` fields identify destination portal hosts. By convention the value
//   is the portal implementation's host ID; core passes it through unchanged
//   and hooks may validate or resolve it for their transport
// - `resources` fields are opaque chain-specific packed words, not native
//   values. A portal adapter interprets them for the destination runtime. EVM
//   resources use the low 128 bits as native value, extracted explicitly with
//   `useResourceValue` before spending.
// - STEP encodes native `value` directly as uint; it does not carry a
//   chain-specific resources word
// - dotted field names and aliases, e.g. `dst.portal` or `#bytes as dst.payload`,
//   are offchain projection metadata only and do not change runtime encoding
// - a dotted schema annotation name, e.g. `relay.input`, instead binds that
//   schema to the encoded block stream inside the aliased `#bytes` field at that
//   structural path; each top-level block carries the content schema's key
// - locally emitted schemas take precedence over active trusted-context and
//   standard schemas with the same name; an invalid selected local schema does
//   not silently fall back
// - `at N` assigns an offchain presentation position to one sibling; explicit
//   positions are reserved first and unannotated siblings retain relative order
// - child blocks resolve by alias in the active schema context; unresolved aliases are invalid
// - the `name:` prefix names the whole schema; `as` independently names an item
// - standard keys have canonical aliases even without an explicit name prefix;
//   a nonstandard key without a prefix remains unnamed
// - items are encoded in declaration order
// - fixed fields are packed inline and any number of child blocks are embedded directly
// - child blocks may appear between fixed fields because each block carries its own length
// - `#bytes` is a reserved child block that stores raw bytes and has no body
// - `#string` is a reserved child block that stores UTF-8 string bytes and has no body
// - generic lists use the stable key derived from `#list`
// - standard keys are derived from block aliases, e.g. bytes4(keccak256("#amount"))
// - custom keys are opaque bytes4 tags and only need to be unique in their
//   active context; use a `#schema` annotation to publish their meaning
// - see `docs/Schema.md` for the full working spec
//
// Pipeline state:
// - command input and state streams are each a single run of blocks under the
//   current protocol convention; the block format may support other shapes in
//   future protocol surfaces
// - balance, debt, custody, and position are the closed set of typed state
//   blocks; custom and dynamic schemas are input and do not extend that set
// - execution generic navigation consumes input, while each typed state block
//   has a dedicated unpacker that consumes state without source selection
// - raw state forwarding is the explicit exception: it consumes state without
//   interpreting or validating the forwarded block types
// - `balance(...)`, `debt(...)`, `custody(...)`, and `position(...)` are live, linear state in the active command pipeline
// - pipeline state belongs to the active account while the pipeline is executing
// - while a balance, debt, or custody is in-flight as pipeline state, it is not simultaneously persisted
//   in another ledger/store by this protocol
// - debt carries only a live liability side; position pairs live balance and debt sides
// - debt quantities are exact net obligations: consuming debt requires satisfying the
//   complete quantity or preserving any unsatisfied remainder as debt state
// - fees and sourcing costs do not reduce fulfilled debt; when fulfillment produces
//   custody, the amount actually reaching custody must equal the consumed debt
// - either position side may be absent by setting both its identifier and quantity to zero,
//   analogous to omitting a transaction side with a zero `from` or `to`
// - debt and position state are transient and do not themselves create or erase an externally persisted obligation
// - positions support backward composition, but pipeline steps always execute in encoded order
// - commands must preserve, transform, settle, or intentionally consume pipeline state
// - input blocks such as `amount(...)`, `allocation(...)`, and `allowance(...)`
//   express intent, constraints, or references
// - input and value/response blocks are not live state
//
/// @title Schemas
/// @notice Human-readable schema string constants for each block type.
/// These strings describe payload layout for discovery events and docs; block
/// aliases and their corresponding keys form the protocol's standard schema
/// catalog. Indexers know these canonical aliases without requiring named
/// schema annotations. Custom blocks may use any unique bytes4 key in their
/// active context.
library Schemas {
    // Empty and reserved payloads

    string constant Bytes = "";
    string constant String = "";
    string constant List = "";

    // Live pipeline state

    string constant Balance = "bytes32 asset, uint amount";
    string constant Custody = "uint host, bytes32 asset, uint amount";
    string constant Position = "bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty";

    // One-word payloads

    string constant Node = "uint node";
    string constant Account = "bytes32 account";
    string constant Asset = "bytes32 asset";
    string constant Status = "uint code";

    /// @dev High 128 bits: inclusive minimum amount; low 128 bits: inclusive maximum debt.
    string constant Limits = "uint limits";

    // Two-word payloads

    string constant Amount = "bytes32 asset, uint amount";
    string constant AssetLiability = "bytes32 asset, bytes32 liability";
    string constant AccountAsset = "bytes32 account, bytes32 asset";
    string constant HostAsset = "uint host, bytes32 asset";

    // Three-word payloads

    string constant Bootstrap = "bytes32 asset, uint amount, uint budget";
    string constant Allocation = "uint host, bytes32 asset, uint amount";
    string constant Allowance = "uint host, bytes32 asset, uint amount";
    string constant AccountAmount = "bytes32 account, bytes32 asset, uint amount";
    string constant HostAmount = "uint host, bytes32 asset, uint amount";
    string constant HostAccountAsset = "uint host, bytes32 account, bytes32 asset";

    // Four-word payloads

    string constant Transaction = "bytes32 from, bytes32 to, bytes32 asset, uint amount";
    string constant HostAccountAmount = "uint host, bytes32 account, bytes32 asset, uint amount";

    // Four-word input payloads

    /// @dev Exact identifiers and packed inclusive quantity bounds.
    string constant Quote = "bytes32 asset, bytes32 liability, uint limits";

    // Composite payloads

    string constant Step = "uint cmd, uint value, #bytes as input";
    string constant Call = "uint target, uint resources, #bytes as payload";
    string constant Relay = "#bytes as input, #bytes as steps";
    string constant Dispatch = "uint portal, uint resources, #bytes as payload";
    string constant Context = "bytes32 account, #bytes as state, #bytes as input";
    string constant Recover = "uint handler, uint resources, bytes32 key, #bytes as witness";
    string constant Annotation = "uint entity, #bytes as data";

    // Annotation payloads

    string constant Action = "uint action";
    string constant Counterparty = "bytes32 account";
    string constant ExecutionCost = "uint base, uint batch";
    string constant Groups = "#string as description";
    string constant Label = "bytes32 namespace, #string as name";
    string constant Schema = "uint spec, #string as body";
}

