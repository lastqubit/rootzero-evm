# Schema

Rootzero input and response data is encoded as a stream of typed blocks. A
schema string describes the payload body for discovery events and tooling; the
runtime block key is the compact type tag that identifies that payload layout in
the active schema context. The block alias comes from an optional `name:` prefix
in the schema string or the protocol's standard key catalog. The prefix names the schema, while
`as` names an individual item within its payload body.

## Wire Format

This section describes blocks. Event category headers have separate fixed layouts;
see [Indexing](Indexing.md#event-categories) and the header of `Logs.sol`.

Every block uses the same header:

```txt
[bytes4 key][uint32 payloadLen][payload]
```

`payloadLen` is big-endian and counts only payload bytes. Child blocks and list
items use the same header format.

Standard built-in block keys use:

```txt
bytes4(keccak256("#name"))
```

The protocol's standard schema catalog defines each built-in key together with
its canonical alias, specification, and body. Indexers must preload this catalog
and therefore know, for example, that the key derived from `#assetAmount` is named
`assetAmount` and has the body `{ bytes32 asset, uint amount }`. This does not depend
on a host emitting a named schema annotation.

If an emitted `#schema` body has no name prefix and its key is standard,
tooling uses that key's canonical standard alias. A nonstandard key without
a prefix remains unnamed. An explicit prefix is required for qualified
bindings such as `relay.input:`.

Custom block keys do not have to be keccak-derived. They
are opaque `bytes4` tags and only need to be unique in the context where they are
used. A host can publish the meaning of a custom key as an annotation:

```txt
[Metadata category:1][subject:32][#schema { uint spec, #string as body }]
```

Standard helpers emit a Metadata category header followed by standard blocks.
General labeling and the admin annotation command are removed; see Indexing.md for
publisher scope, endpoint resolution and historical ABI compatibility.

Annotation merge behavior is defined by the annotation block type rather than
by the event header. A `#schema` annotation is identified by its entity
and the block key encoded in `spec`: distinct keys accumulate, while the latest
trusted claim for the same key replaces the earlier one. Other annotation types
may define additive, historical, or explicitly revocable behavior instead.

The standard `#counterparty { bytes32 account }` annotation assigns a counterparty
account to an entity such as a command or asset. The latest trusted value replaces
the previous account, and zero identifies Rootzero. Host accounts use the same
representation as in POSITION. The annotation identifies the counterparty, not
whether to settle or realize it. Like other annotation helpers, it encodes the
claim without validating either ID; consumers apply type and trust policy.

Execution-cost estimates are maintained off-chain per command. The execution-cost
annotation helper, block key, spec and schema have been removed.

For example, a host-specific payment block can use a small literal, the command
selector, or any other chosen `bytes4` value as long as that key is not
overloaded in the relevant host/schema context.

## Block Syntax

A schema string has the form `[name ":"] body`. The optional name prefix
appears only at the beginning, outside any body braces. A body is one of
these forms:

```txt
""                  empty or raw payload
fields              structured payload
{ fields }          equivalent braced structured payload
many #item          top-level custom list payload
{ many #item }      equivalent braced top-level list payload
```

One optional pair of outer braces may wrap any non-empty schema body. The
braces are presentation-only and never change its wire layout:

```txt
assetAmount: bytes32 asset, uint amount
assetAmount: { bytes32 asset, uint amount }
```

After extracting any name prefix, consumers must remove one matching pair of
outer braces, when present, before parsing the item sequence. Only commas
outside alias-list parentheses separate sibling items. Unmatched braces and
additional outer brace layers are invalid.

A block body can reference another block alias as a child item with `#`:

```txt
{ bytes32 account, #state, #input }
```

The empty schema string `""` means the block has no structured payload. This is
used for raw dynamic blocks such as `#bytes`.

Payload validity is defined by each block's schema. `#bytes`, `#string`, and
lists accept zero-length payloads. Fixed-size blocks still require their full
payload, even when every value is zero. Composite blocks must contain their
declared fields and child headers in declaration order. There is no universal
empty-block marker or implicit omission of a child.

A structured schema body is a comma-separated list of items. Order is
significant.

```txt
{ #assetAmount, #account as recipient }
```

### Repeated-reference shorthand

A schema reference may declare two or more aliases in parentheses:

```txt
#accountAmount as (debit, credit)
```

This is syntax sugar for consecutive child references, in the same order:

```txt
#accountAmount as debit, #accountAmount as credit
```

Consumers expand this form before schema resolution, layout calculation, and
projection. Each alias produces one child with the referenced schema's original
key. The parentheses introduce no block, list, tuple value, or extra header.
The surrounding custom parent and its wire encoding are identical for both forms.
Schema annotations may publish either spelling; they are not rewritten onchain.

The shorthand applies only to an unmodified `#schema` reference, which must
resolve in the active schema context. It does not apply to inline field types
such as `uint`. The alias list must contain at least two ordinary alias paths,
separated by commas; dotted paths follow the existing field-path rules.
Empty or single-alias lists, empty entries, trailing commas, nested parentheses,
and duplicate or colliding alias paths are invalid. Use `#schema as alias` for
one alias. Use the expanded form for `many` or per-item `at` modifiers.

For example, this is valid alongside ordinary sibling items:

```txt
uint id, #bytes as (source.payload, destination.payload), #account as owner
```

Commas inside the parentheses separate aliases, not schema items. After
expansion, all ordinary sibling validation and presentation rules apply.

### Optional schema name

The prefix names the whole schema independently of field names and `as` aliases:

```txt
assets: many #asset as assets
portfolio: many #asset as holdings
relay.input: uint portal, uint resources
opaque:
```

The first example declares a schema named `assets` and gives its list item the
presentation name `assets`. The second declares `portfolio` with a list named
`holdings`. References use `#assets` or `#portfolio`; neither prefix nor field
alias adds a container or changes the key in `spec`. The existing top-level
`many` rule still uses that key as the outer list block key.

Consumers first extract the optional prefix, then parse the remaining body.
Whitespace around the name, colon, and body is insignificant. Names follow the
identifier/path grammar below, are case-sensitive, and have no 32-byte limit.
Exactly one prefix is allowed, only at the start and outside braces. Empty
names, invalid identifiers, additional colons, and nested declarations are
invalid; consumers must reject them rather than treating them as unnamed.
For example, `: uint value`, `bad-name: uint value`, `a: b: uint value`, and
`{ assets: many #asset }` are invalid.

An empty remaining body, as in `opaque:`, has the same empty/raw meaning as an
unnamed empty string. Empty braces remain invalid. A malformed selected schema
does not fall back to a standard schema. Name resolution and trusted-context
precedence are unchanged. Solidity helpers encode the complete string without
parsing or validating this offchain DSL.

The `#schema` payload is `uint spec, #string as body`, with a minimum payload
length of 40 bytes. There is no separate name word. This replaces the previous
`uint spec, #string as body, bytes32 name` wire format; consumers must migrate
alongside producers rather than accepting the trailing word as part of the body.

## State and Input containers

`#state` and `#input` are variable-length containers for encoded block streams.
Each uses the standard eight-byte header and permits an empty payload. Child
schemas are determined by the endpoint or enclosing protocol. Like `#list`, their
catalog schema strings are empty because no single child layout is prescribed.
Their unbounded specs have a zero minimum and a 128-byte allocation hint.

CONTEXT is `bytes32 account, #state, #input`; STEP is
`uint cmd, uint value, #input`; RELAY is `#input, #bytes as steps`.
The RELAY steps payload remains an encoded STEP stream inside BYTES.
These typed wrappers replace the former BYTES wrappers without changing offsets
or total encoded sizes. Old BYTES children are rejected in the migrated positions;
producers and consumers must migrate together.

Standalone containers can use `Encoder.createBlock(Keys.State, state)` and
`Encoder.createBlock(Keys.Input, input)`. Context creators and wrapping writers
construct these headers automatically. Complete-child writers expect the typed
headers to be included already.

Encoders copy payloads without recursively validating them. Container decoding
checks keys, lengths, order, and boundaries, then returns payload cursors that
exclude the wrapper headers. Commands validate their own payload schemas.
Runner logs retain STATE/INPUT container headers and wrap output in OUTPUT.
Returned output streams remain unwrapped.

Within `#groups` metadata, `#state` and `#input` retain their contextual meaning
as endpoint lane references; this is distinct from their container block keys.

## Payload Layout

A block payload encodes schema items in declaration order. Fixed fields are
packed inline, and zero or more child blocks are embedded directly at their
declared positions. Because every child block carries its own header and payload
length, fixed fields may appear before, after, or between child blocks.

```txt
{ uint target, uint value, #bytes as payload }
{ bytes32 account, #state, #input }
{ uint spec, #string as body }
{ #bytes as left, uint op, #bytes as right }
```

There is no wrapper around embedded child blocks.

Raw dynamic bytes are represented with the reserved `#bytes` child block. Use an
alias to give those bytes a presentation name:

```txt
#bytes as payload
```

### Qualified byte-content schemas

An aliased `#bytes` field remains opaque unless its active schema context
contains a schema whose name exactly matches the field's qualified structural
path. That named schema identifies the top-level blocks encoded inside the byte
payload. Each contained block uses the ordinary header and payload format, so
onchain implementations can open the bytes with a decoder, use existing unpack
helpers, and close the decoder to reject trailing or malformed data.

For example, the standard relay envelope is:

```txt
relay { #input, #bytes as steps }
```

A relay implementation can publish its transport-specific input shape with the
existing schema annotation helper:

```solidity
schema(
    "relay.input: uint portal, uint resources",
    inputSpec
);
```

Tooling then decodes `relay.input` as a stream of blocks carrying the key from
`inputSpec`; each block payload contains the two declared fields. The spec's
size fields constrain each block payload exactly as they do elsewhere. A
single-value implementation can validate the complete slice directly, while a
batch implementation loops with a decoder and then closes it. Without a
matching qualified schema, tooling leaves the bytes opaque. The standard
`relay.steps` convention likewise contains an encoded STEP stream.

For example, a relay implementation can consume exactly one configuration block
without defining a second headerless decoding convention:

```solidity
uint body = Blocks.exact(input, inputSpec);
uint portal = uint(Blocks.read32(body));
uint resources = uint(Blocks.read32(body + 32));
```

`Blocks.exact` requires the decoded block to occupy the complete calldata slice.
The lower-level `Blocks.enter` helper instead returns the slice's absolute
`limit` without enforcing `end <= limit` or `end == limit`, allowing direct
callers to perform the comparison they require. A `uint abs` overload provides
the same raw entry operation without a slice limit when the caller already has
an absolute calldata position.

If an application truly needs opaque bytes, it can encode a `#bytes` or custom
raw-payload block inside the qualified field. The containing block header remains
present.

Qualified schema names and dotted field aliases use the same path syntax but
serve different purposes. A dotted alias inside a schema body controls
offchain projection, while a dotted name on a `#schema` annotation binds a
content schema to an aliased byte field. For example:

```txt
#bytes as dst.payload       // projection path inside a body
relay.dst.payload           // qualified content-schema name
```

Schema resolution prefers claims emitted locally by the host exposing the
endpoint over schemas available from active trusted contexts, which in turn
take precedence over standard schemas. A claim is local only when both its
emitter is the active host and its annotated entity is that host's own ID. For
the same name, the latest local claim in log order wins and replaces the
fallback rather than merging with it. If that selected local schema is invalid
or has unresolved references, tooling reports the error instead of silently
falling back to another schema.

## Modifiers

Repeated items are expressed with the `many` prefix:

```txt
#balance
many #balance
```

- no prefix: one required item, validated according to its block schema
- `many`: one required list header containing zero or more repeated items

These are offchain descriptions of the forms accepted by the onchain consumer;
they do not change runtime validation. Empty bytes, strings, and lists are
ordinary values. Optional-value encoding must be explicitly defined by the
application's schema and consumer; there is no optional-item modifier.

A `many` item alongside any sibling items wraps its repeated values in one
generic `#list` block; it does not repeat the item in place. The list header
remains present when it has no items and carries a zero payload length:

```txt
{ uint id, many #asset as assets }
```

When the item sequence of an emitted custom schema consists of exactly one
`many` item, the custom schema key identifies the outer list block instead. Its
payload contains the repeated items directly. Optional outer braces and an
item alias do not affect this rule:

```txt
schema key: 0x00000001
schema body: many #asset
equivalent body: { many #asset }
also equivalent: many #asset as assets
wire value: [0x00000001][length][ASSET][ASSET]...
```

This convention gives a top-level list a discoverable, context-local type while
retaining the generic `#list` key for lists whose type is supplied by an
enclosing schema.

## Fixed Compositions

Use ordinary child references to describe a fixed composition inside a custom
parent block. Each child has its existing schema key and may have a role alias:

```txt
schema key:  0x00000001 (local key published by the host)
schema name: omitted (unnamed)
schema body: #accountAmount as (debit, credit)
expanded:    #accountAmount as debit, #accountAmount as credit
wire:        [0x00000001][208][ACCOUNT_AMOUNT debit][ACCOUNT_AMOUNT credit]
```

The parent schema identifies one complete operation; batching repeats that parent.
This remains available for custom compositions. `portBook` instead uses the canonical
`#booking` schema:

```text
bytes32 from, bytes32 to, bytes32 liability, uint debt, bytes32 asset, uint amount
```

Its payload is 192 bytes and its complete block is 200 bytes. Each block debits
`debt` of `liability` from `from`, then credits `amount` of `asset` to `to`.
The accounts and assets may differ; zero quantities omit their respective legs.
`Booking` is the matching Solidity struct. Codec and execution helpers accept
or return that struct, and `BookHook.book(Booking memory value)` applies it.
Hooks must not mutate the supplied value. `Settlement.book(Booking)` forwards to
the virtual scalar `book(from, to, liability, debt, asset, amount)` implementation.
Settlement extensions override the scalar version to customize both paths. Direct
scalar callers allocate no temporary Booking; overriding only the struct version
affects struct callers only.

The input lane is `Specs.Booking` without operation logging. Account hooks own
updated-balance logging with explicit account and asset IDs; no active Pipeline
account is needed. A reverted booking removes the entire batch's effects and logs.

This replaces the former pair of ACCOUNT_AMOUNT blocks (208 bytes). Callers must
migrate to BOOKING; old pairs are rejected. The grouping annotation is no longer needed.

## Asset Preimages

`#assetPreimage` has schema `bytes32 asset, #bytes as preimage`.
Its payload is 40 bytes plus the preimage length; the complete block is 48 bytes
plus that length. The BYTES child must occupy the remainder of the parent exactly.
`Keys.AssetPreimage`, `Specs.AssetPreimage` and `Schemas.AssetPreimage`
define the layout; the spec has minimum 40, unbounded maximum and hint 256.
`Encoder.createAssetPreimage` preserves the complete preimage without validating
its hash or implying host support. Emit existing blocks through endpoint lane
logging or `Logs.metadata(uint(asset), data)`.

For opaque keccak asset IDs, require at least three preimage bytes, hash-format
byte 0x01 and the Asset category byte. Verify
`asset == 0x02 || preimage[1:3] || bytes29(keccak256(preimage))`.
Unknown hash formats require their own rules. Keep the emitting publisher with
the claim; malformed or mismatched claims must not become verified preimages.
Asset operation meaning comes from the endpoint policy; its execution lanes
can contain standard `#asset` blocks.

## Transport envelopes

`#envelope` has schema `uint portal, uint resources, bytes32 key, bytes32 digest`.
Its key is bytes4(keccak256("#envelope")); the payload is exactly 128 bytes,
136 including the header. Keys/Specs/Sizes/Headers/Schemas.Envelope define it.
Encoder.createEnvelope preserves the four full-width fields without validation.

portal identifies the destination portal host. resources is chain-specific.
key is an independent transport correlation or recovery lookup key.
digest is keccak256 of the exact forwarded payload bytes, excluding Envelope
routing fields and block headers unless those bytes are themselves part of the
forwarded payload. This matches Portal's witness hashing convention.

`Logs.envelope(portal, resources, key, digest)` emits a fixed Envelope
category record: category byte followed by four full-width fields.
It is 129 bytes, has no topics, and contains no ENVELOPE block header. The block
codec remains available separately. The helper neither computes the digest nor
sends a message. A separately published payload must match the digest.

Relay/Dispatch input schemas and runners are unchanged. The legacy Relay and
Dispatch ABI-event mixins have been removed; applications choose where to emit envelopes.

## Resolution records

`#resolution` has schema `bytes32 key, bytes32 digest`: exactly 64 payload bytes,
72 bytes including the header. Keys/Specs/Sizes/Headers/Schemas.Resolution define
the canonical block layout. Encoder.createResolution constructs it.
`Logs.resolution(key, digest, resolved)` emits a separate 66-byte category record:
category, key, digest, and one boolean byte (0 unresolved, 1 resolved).
The key and digest identify a recovery record on the emitting host. The helper
does not mutate storage or verify witnesses.
Resolved denotes consumption of a matching record. It does not certify downstream
delivery separately, and subsequent transaction reverts discard the log.

## Host Introduction

The canonical `#introduction` schema is `uint peer, bytes32 origin, uint blocknum`.
Its payload is exactly 96 bytes (104 including the header).
`Keys.Introduction`, `Specs.Introduction`, `Sizes.Introduction`,
`Headers.Introduction` and `Schemas.Introduction` define the layout.
`Encoder.createIntroduction` constructs the block. `Logs.introduction` emits a
category record containing the three fields followed by raw UTF-8 name bytes,
without a block wrapper or a name length field (97 + name byte length).
The receiving host is identified by the emitter.
The host validates the peer against the caller; origin is transaction provenance,
and blocknum is an unverified caller-supplied claim. Introduction grants no trust.
The name is a nonunique discovery hint, not an identifier. Hosts without an
introduction remain identifiable by host ID. Indexers preload the event layout
for discovery; the standard block schema above describes only the fixed fields.

## Endpoint Registration

The canonical `#endpoint` schema is `uint id, uint state, uint input, uint output`.
Its payload is exactly 128 bytes (136 including the block header). Specs are pure;
flags select logged lanes. `Keys.Endpoint`, `Specs.Endpoint`, `Sizes.Endpoint`,
`Headers.Endpoint` and `Schemas.Endpoint` define this layout. `Encoder.createEndpoint`
constructs the block; `Logs.endpoint` emits category 0x05, those four fields, and
the registration name as trailing raw UTF-8 bytes (129 + name byte length).
There is no block wrapper, name length field or padding. Indexers preload this
layout to decode discovery. Endpoint names no longer require LABEL metadata.

## Endpoint Lanes

Logging policy is encoded in the endpoint ID flags byte alongside behavior flags.
Bits 2/3/4/5 mean Execution/State/Input/Output; lane flags include Execution:
`Logs.Execution=4`, `Logs.State=12`, `Logs.Input=20`, `Logs.Output=36`.
Bit 0 is Funded, bit 1 Admin, bit 6 endpoint-defined and bit 7 Handoff.
Registration takes one flags argument; lane bits without Execution are rejected.
Endpoint identity and logging policy are fixed at deployment. Tags and custom effects are
maintained offchain; see [Indexing](Indexing.md#offchain-interpretation).
Specs with nonzero lower halves are rejected by endpoint registration.
Each spec identifies its top-level block key and retains bounds and hints. Each block
represents one operation; fixed compositions use a custom parent block.
Solidity endpoint helpers accept specs such as `Specs.AssetAmount`, while
`Specs.Empty` declares an absent lane. There is no stride or group multiplier.

Registration separately derives an internal execution descriptor for opening and
allocation; it is not published in Endpoint events. Its layout, from most to
least significant byte, is:

```txt
[source key:4][source block size:4][output block size:4][reserved:19][flags:1]
```

Endpoint loop grouping is described separately by a `#groups` annotation on the
endpoint ID. Its payload schema is `#string as description`. For example:

```txt
#state as (debit, credit), #output as (receipt, change)
```

This is a dedicated annotation language, not a block payload schema. Only
`#state`, `#input`, and `#output` are lane references; each resolves to the
corresponding published endpoint spec. An entry is a lane reference followed by `as`
and a parenthesized list of at least two aliases. Commas outside parentheses
separate entries. Each lane may appear once. Aliases use the ordinary schema
alias-path rules; duplicate or colliding aliases within a lane are invalid.
Alias order describes consecutive blocks within one loop iteration. No wrapper
or extra block header is added, and no global schema aliases are introduced.

Only grouped lanes are listed; omitted lanes have no grouping hint. Published endpoint
specs take precedence: entries for empty lanes are ignored and cannot create
blocks. Group counts are implied by the alias lists, not stored in descriptors.
Annotations affect neither decoding, allocation, nor runtime enforcement.
Execution output allocation uses descriptor hints and grows when needed.
Indexers can use the description to interpret repeated loop groups; incompatible
streams should be reported as inconsistent hints, not reinterpreted as new encoding.

`GroupsAnnot.annotateGroups(endpointId, description)` publishes the string without
on-chain syntax validation. The latest annotation from a trusted emitter replaces
the previous whole description; an empty string clears the hints. Invalid selected
annotations should be reported by tooling rather than silently falling back to an
older description. Trust remains the consumer's responsibility.

The allocation source is declared state when present, otherwise input, even when
supplied state is empty. Block sizes include the header; 32-bit fields preserve
the full 24-bit payload hint plus that header. Zero output size disables initial
allocation. With no source key, opening reserves one output block.

Internal flags are `StateSource = 1`, `LogState = 2`, `LogInput = 4`,
`LogOutput = 8`, `LogEnabled = 16`, and `ByteCapacity = 32`.
`Executions.describe(state, input, output, flags)` derives enabled
logging from its packed flags and precomputes equal-fixed-stride capacity hints. The
three-spec overload is silent. Public endpoint behavior flags stay in the ID.
Descriptors carry allocation and logging instructions, not complete schemas.

Solidity code constructs this metadata with `Executions.describe`. The same
library initializes an `Execution` through `exec.openContext` or `exec.openInput`;
their independent state/input cursors use the standard Cursors range layout.
`exec.openContext` initializes the
command account and an explicit native-value budget together with both sources
and the output writer. Input-only endpoints use `exec.openInput`, which accepts
an explicit budget but no command account. Passing the budget explicitly keeps
both opening helpers pure and supports callers that forward an existing budget.
Both in-place helpers expect a newly allocated or otherwise empty `Execution`.
When logging is enabled, opening snapshots selected sources into a prefix of the
output buffer. Commands reserve ID and account, input-only endpoints only ID.
Selected empty lanes retain their container headers. `finish(id, descriptor)`
emits one completion event and returns an alias to output after replacing part
of the prefix with a bytes length word. `finish()` is silent. Both finalize once;
the old event prefix must not be reused. No log prefix is allocated when disabled.
The output cursor retains its payload-start offset in bits 64-95 across growth.

`Cursors` supplies shared range primitives: `create(abs, endAbs)` validates bounds,
while `pack(abs, endAbs)` packs already validated positions without repeating checks.
Cursors encode an absolute current position (bits 0-31) and exclusive end
(bits 32-63). Upper bits may carry caller-defined metadata: navigation preserves
it, constructors and child slices clear it, and conversions and hashing ignore it.
There is no cursor flag API.
`length`, `more`, `done`, `expectEnd`, and `exhaust` handle inspection and consumption.
`done` checks exact equality, so a reversed range is not considered consumed.
Use it when a caller needs its own error; `expectEnd` reverts UnconsumedData.
`enter(cur, amount)` validates a raw byte range and returns `(abs, nextCur)`;
it does not inspect block headers. `take(cur, amount)` instead returns
`(sliceCur, nextCur)`, with a clean child cursor over the consumed raw bytes.
`toBytes`, `toBytesChecked`, `toString`, and `toStringChecked` expose calldata views;
checked variants validate bounds, not block structure or UTF-8. `hash` hashes the
remaining calldata range using temporary memory. Blocks keeps thin wrappers for
these conversions and hashing. Positions used by `seek`, `expect`, and `slice`
are absolute. Encoder continues to use its separate relative offset/capacity model.

Flag bits 0 and 1 are the protocol-defined `funded` and `admin` flags. Bit 7 is
the protocol-defined `handoff` flag, bit 6 is reserved for endpoint-defined
behavior, and bits 2 through 5 select logging as part of the same endpoint identity.

Execution stores input and state in independent uint cursors, each using bits
0-63 for current/end. Source selection belongs to the descriptor, not
the cursors. Buffer writers use bits 0-63 for their relative offset/capacity.

Specs pack `[key:4][min:4][max:4][hint:3][reserved:17]` from most to least
significant byte. `Specs.blockSize` adds the header to the payload hint;
`Specs.allocation(spec, count)` reserves that size for each top-level block.
Descriptors retain precomputed block sizes rather than full specs.

Any non-empty lane resolves its key to a block alias and schema body through the
active schema context. A top-level list lane uses the key of its emitted custom
`many` schema; a fixed-composition lane similarly uses its custom parent key.
Each parent is one operation, and its children retain their own keys.

The lane key is the prime item. Prime items may repeat at the top level for
batching. Later top-level items are globals for the whole batch and are not
counted as per-operation prime blocks.

Each prime block must satisfy its payload schema. An empty stream represents
zero operations; a zero-length block is valid only when its schema permits it,
as with bytes, strings, or lists.

Execution cursor opening wraps the supplied state and input calldata without
validating their published lane specs. The descriptor source key is only an
allocation hint. When output is declared, writer pre-sizing may count the consecutive
prime-block run from declared state, or input when state is absent. Divisible
source lengths use the precomputed block size directly; the fallback scan is an
allocation hint only. The writer remains resizable. Block schema and boundary
checks happen when command code consumes each block, and execution finalization
rejects any unread state or input bytes. Command decoding and loop structure
are therefore the runtime source of truth for source cardinality and whether an
empty source is accepted.

For commands, complete-source validation is also a state-safety rule. State is a
linear value owned by the current pipeline step, not optional context that a
command may disregard. Every command must account for the complete supplied
state by consuming it, transforming and returning it, forwarding it intact with
`takeState` or `takeStateFixed`, or reverting. Descriptor metadata alone does not reject a source;
a command that leaves supplied state unread rejects it when closing. Ordinary
typed consumption validates blocks against the type requested by the command.
Whole-stream forwarding validates the keys or fixed headers requested by the
command; descriptor metadata alone does not perform that validation.

## Live Pipeline State

STEP command IDs use subtype `0x03` and encode public endpoint flags in the
last byte of the ID type field. Flag bit 7 and the envelope
`relay { #input, #bytes as steps }` identify handoff commands.
`Pipeline.pipe` automatically places the flagged STEP's ordinary input and the
untouched remaining STEP stream in this envelope, then transfers ownership of
that continuation to the command.

`#balance`, `#custody`, and `#position` are live state carried between
command steps for the active account. Balance carries only the asset side;
a position can carry either or both sides:

```txt
balance  { bytes32 asset, uint amount }
custody  { uint host, bytes32 asset, uint amount }
position { bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty }
```

These three standard aliases form the protocol's closed set of typed state
blocks. Custom schemas and dynamic composite blocks are command input, not new
state types. This distinction is enforced by the execution API: generic
navigation and custom-schema helpers consume input, while `unpackBalance`,
`unpackCustody` and `unpackPosition` consume state directly.
Callers do not select or switch an active decoder source. `Execution.input`
and `Execution.state` are separate `uint` calldata cursors, each storing the
absolute current position in bits 0-31 and end in bits 32-63. Higher bits
are unused. Updating one cursor leaves the other source unchanged. The former combined `Execution.decoders` field has been removed.

Whole-stream validation belongs to Blocks: `expectRun(cur, key)` checks every
block's key and containment, while `expectRunFixed(cur, header)` also checks exact
payload sizes. Both accept empty streams and require established calldata bounds.
Executions provides thin `takeInput`/`takeState` and `takeInputFixed`/`takeStateFixed`
wrappers that trust the calldata bounds established during opening, delegate
stream validation, and consume only
the selected lane. They return cursors over complete blocks, regardless of descriptor declarations.
The requested key or header determines validation. Close rejects any bytes left
unread in either source; declaring a source EMPTY does not hide supplied data.
Use `toBytesChecked()` when a calldata view is needed; cursors can otherwise be
forwarded directly. `takeBalances` delegates to `takeStateFixed` with the BALANCE header;
`relayBalancePayable` uses it to reject other state types and malformed blocks.
An empty stream is accepted. Adding another typed pipeline-state
shape therefore requires a standard protocol block and a dedicated execution
unpacker; publishing a custom schema alone does not create a state type.

`debt` is an exact net obligation. Consuming a position liability means satisfying its
complete quantity; a command that cannot do so must revert or return the
unsatisfied remainder in a position. Fees and sourcing costs are additional to
that quantity and must not silently reduce it. If fulfillment creates custody,
the amount actually placed in custody must equal the consumed debt quantity.

The two sides of a position are independently optional. Encode an absent asset
side as `asset = 0, amount = 0`, and an absent liability side as
`liability = 0, debt = 0`. This follows the same convention as a transaction
whose zero `from` or `to` omits that side. One-sided positions allow a command
to retain a position-shaped output for later composition. Debt is represented
only as a position with `asset = 0, amount = 0`. `#balance` remains available
for asset-only state.

`counterparty` is a 32-byte identifier. Generic position writers and unpackers
preserve it. Zero names Rootzero and uses the booking path.
`unpackPosition` returns all five fields without a counterparty check;
account format follows the [boundary-validation convention](../README.md#account-validation-convention).
The payload is 160 bytes (168 bytes including its header). The old 128-byte
POSITION payload and standalone DEBT schema are no longer accepted.

### Counterparty Semantics

The counterparty identifies who stands on the other side of the position:

| Counterparty | Command | Intended behavior |
| --- | --- | --- |
| `0` (Rootzero) | `settle` | Debit the active account's liability and credit its asset. |
| Account ID | `settle` | Debit the asset amount from that account and credit the active account; debit the liability amount from the active account and credit the counterparty. Both transfers are atomic and require the host's applicable authorization. |
| Host account ID | `settle` or `realize` | Settle against this account's balances on the executing host, or route to its host for realization. The realization hook matches `Accounts.toHost(host)` and returns counterparty zero after fulfillment. |

Every nonzero POSITION counterparty is an account ID. Host node IDs are not
position counterparties. The host account subtype alone does not choose the
operation or destination: offchain routing metadata and balance availability
determine whether to settle on a particular host or invoke realization.
The command does not automatically forward positions. Realization must fulfill
the obligation before clearing the counterparty; changing the field alone is
not fulfillment.

**Current stage:** codecs support any counterparty. `settle`, `settlePayable`,
and `ExecuteSettle` pass the complete `Position` struct to the hook. Calldata
commands use `Executions.unpackPositionValue`; the memory adapter uses
`Execute.unpackPositionMemory` after `Execute.bounds` to decode the same struct. The hooks are `settle(account, position)` and
`settle(account, position, funds)` for funded settlement. Hooks retain applicable
authorization and fulfillment requirements; account format is trusted after
validation at the untrusted-input boundary.
`Settlement` implements the unfunded hook. Producers enforce limits before
emitting positions; settlement books zero-counterparty positions on the active
account.
Nonzero counterparties are passed unchanged to the account hooks when transferring
the exact debt followed by the exact asset amount. Authorization remains with
trusted position producers and host account hooks. `debitAccount`, `creditAccount`,
and custom `BookHook` implementations may assume account arguments satisfy the
caller's account policy; they need not repeat account-format checks. Commands
accepting user-supplied accounts must validate them before using them, emitting
positions, or forwarding them. Trusted peers own the validity of supplied accounts;
a receiving host does not guarantee rejection of malformed accounts from a faulty
trusted integration. Empty exchanges skip the account hooks and do not validate
the counterparty. Funded settlement still uses
the host's separate hook with the same exact-quantity requirements.

`settle` consumes POSITION state with empty input and output. `ExecuteSettle`
provides the same settlement hook for memory-backed
pipeline state. For zero counterparties it calls
`book(account, account, liability, debt, asset, amount)`. `BookHook` remains
defined in `core/Settlement.sol`; its default implementation debits the exact
liability amount and then credits the exact asset amount. Zero amounts skip
account hooks, and any failure reverts the whole operation.

The former `book` command is removed. `settle` accepts account counterparties and
applies final quantities without checking limits; producers must enforce their
quantity constraints. Callers that require an already-realized
position must explicitly check `position.counterparty == bytes32(0)` separately
from `checkPosition` or `Blocks.expectPositionConstraints`. A trusted
realization hook must return counterparty zero before handing the result onward.

The same `BookHook` is used directly by `portBook` and settlement for its
exact transfers. The `BookHook` signature is
`book(Booking memory value)`. It must apply both exact legs
or revert, skip zero-amount legs, and preserve debit-first funding requirements
even when accounts or assets match. It does not net legs or interpret a zero
account as an absent side. Callers encode zero debt or amount to omit a leg.
`portBook` validates the complete BOOKING before calling the hook, so a malformed
block is rejected before debiting. This structural check does not validate the encoded account's format.

`realize` passes the complete position to its hook, which matches the intended host
account counterparty and fulfills the obligation before returning counterparty zero.
This operation-specific match remains required even when account format is trusted.
The command takes empty input and returns the fulfilled positions. Callers may
append `checkPosition` with POSITION_CONSTRAINTS to validate the final outcome.
The hook remains responsible for preserving asset/liability identifiers and
fulfilling the intended counterparty obligation; it need not recheck account format.

### Position Transformations

The position layout is flat, with both sides followed by the counterparty;
it is not a nested Solidity struct. The asset side represents
value acquired or controlled, and the liability side represents value owed or
required. Commands may preserve or replace either side and return a new
position. The terminal `settle` command exchanges with an account counterparty
or applies a zero-counterparty booking. Positions, including
liability-only positions, are transient state; rewriting them does not by itself create,
discharge, or replace an obligation persisted by a host or external protocol.
The responsible command hook must perform or verify those effects. A command
must not ignore supplied position state: it must explicitly consume,
transform, forward, or reject it, so an obligation cannot disappear
accidentally.

`settle` and `settlePayable` consume positions, including liability-only
positions, and return empty state. To repay, use a POSITION with zero asset and
amount. The separate `repay` command uses `RepayHook` to discharge a liability
while preserving any asset side in the returned position. Hosts
implement settlement, which routes the liability transfer through
`BookHook.book`. A position with an asset side also settles that side instead
of returning a BALANCE block.
The single `realize` command calls one hook:

```solidity
function realize(bytes32 account, Position memory position) internal virtual returns (Position memory);
```

The hook fulfills both sides in their existing asset and liability denominations.
It enforces counterparty authorization and operation-specific matching, trusts
account format under the boundary convention, chooses its internal order, and returns
the complete realized position with counterparty zero. It must fulfill the entire
obligation or revert: no source remainder is emitted, and fees or rounding must
not silently discard debt. The command accepts empty input and returns the
hook's results without applying caller constraints. The hook remains responsible
for preserving asset/liability identifiers and fulfilling the intended counterparty
obligation; it need not recheck account format.

The standalone `#limits { uint limits }` schema carries a general packed
minimum and maximum: the high 128 bits are the inclusive minimum, and the low
128 bits are the inclusive maximum. The consuming context determines what
each bound applies to. Its payload is 32 bytes (40 with the header). Both lanes
are literal bounds: `type(uint128).max` is a cap, not an unlimited sentinel.
It identifies no asset, liability, or counterparty.

- With a POSITION, the minimum applies to the net asset amount and the maximum
  applies to total liability debt, including fees: `position.amount >= minimum`
  and `position.debt <= maximum`. These are separate quantities, so the minimum
  need not be less than or equal to the maximum. Position quantities remain
  full-width uints; output amounts may exceed 128 bits, but debt cannot exceed the cap.
- With a BALANCE, both bounds apply to its amount:
  `minimum <= balance.amount <= maximum`. A minimum greater than the maximum
  describes an empty range that no balance can satisfy.

Pack with `(minimum << 128) | maximum` after ensuring both inputs fit uint128.
`unpackLimits` returns the packed uint from calldata, cursor, execution, or memory
sources. Encoder and execution outputs accept that same word. Codec helpers
validate the block header and preserve the value without enforcing quantities.

The separate `#balanceConstraints { bytes32 asset, uint min, uint max }` schema adds an
exact asset identifier and uses full-width uint256 bounds. Its payload is 96
bytes (104 including the header), ordered as asset, minimum, maximum. Both
bounds are inclusive and literal; zero and `type(uint256).max` are not sentinels.
An inverted range cannot be satisfied. Codecs preserve inverted ranges without
enforcing them. `Specs.BalanceConstraints`, `Sizes.BalanceConstraints`, `Headers.BalanceConstraints`,
and `Schemas.BalanceConstraints` describe this shape. Offchain callers encode these
constraints. `Blocks.unpackBalanceConstraints` consumes a bounded calldata cursor,
and `Executions.unpackBalanceConstraints` consumes the execution input lane;
both return `BalanceConstraints { asset, min, max }`.
There are no onchain BALANCE_CONSTRAINTS writers, factories, or output helpers.

`Blocks.expectBalanceConstraints(abs, asset, amount)` checks the header, exact asset,
and inclusive amount bounds directly in calldata without unpacking. The caller
must bound the complete block. `Executions.expectBalanceConstraints(exec, asset, amount)`
bounds and consumes one BALANCE_CONSTRAINTS input before delegating to it. A bad header
reverts with `InvalidBlock`, an asset mismatch with `UnexpectedValue`, and a
violated bound with `OutOfRange`, in that order. `CheckBalance` uses this helper.

`checkBalance` (`CheckBalance` in `commands/Balance.sol`) accepts BALANCE state
and one BALANCE_CONSTRAINTS input per balance. It checks exact asset identity, then
`min <= amount <= max`, and returns each balance unchanged. A mismatched asset
reverts with `UnexpectedValue`; a violated bound reverts with `OutOfRange`.
It does not check authorization or backing. Empty state with empty input is
valid; missing, extra, malformed, or failing constraints revert the call.
Packed LIMITS input is not accepted by this command. The generic packed LIMITS
schema remains available for contexts that already establish asset identity.

`ExecuteCheckBalance` adds internal execution for the same command ID. It checks
memory BALANCE blocks directly against calldata BALANCE_CONSTRAINTS in assembly without
unpacking or copying, returning the original state buffer and unused native
budget. Hosts route `checkBalanceId()` to
`executeCheckBalance(account, state, input, value)` in their local dispatcher.
The normal command uses the standard execution callback and output writer.

`Blocks.expectLimits(abs, amount, debt)` checks the LIMITS header and compares
full-width quantities directly against its calldata payload. The caller must bound
the complete block. `Executions.expectLimits(exec, amount, debt)` bounds and
consumes one LIMITS input before delegating to it. These helpers remain available
for operations that consume generic packed bounds.

`settle` and `settlePayable` consume any number of POSITION blocks with empty
input. `ExecuteSettle` rejects nonempty input with `UnexpectedInput`, establishes
fixed-size memory bounds, and iterates the position stream. Partial blocks revert
with `InvalidBlock` when establishing bounds. The settlement hook validates and
authorizes the counterparty. Callers may enforce final outcome constraints with
`checkPosition` before settlement. `Realize` takes empty input; it does not apply
quantity constraints.
`Settlement` supplies a default `settle` implementation without host fees.
Producers handle fees before creating the position: `amount` is the final net
asset receipt and `debt` is the final total payment. Settlement applies those
quantities exactly, without surcharges, asset deductions, or separate host fee
credits. Limits protect the encoded quantities, not separate charges outside
the position. Producers must arrange any separate fee payments atomically.

For account counterparties, settlement calls `book` for the full liability
transfer first, then for the full asset transfer. Zero-quantity transfers skip
their hooks. Any failure reverts the entire exchange. Specialized hosts may
override `settle` while preserving its exact-quantity contract.

Commands that consume LIMITS reject missing, extra, or malformed limits.
Settlement rejects all nonempty input.

`repay` accepts POSITION state and empty input and returns one POSITION per
source position, preserving every field except `debt`, which becomes zero.
The unfunded `RepayHook` must satisfy the
complete exact debt or revert and must not mutate its position argument; the
command clears debt only after the hook succeeds. `Settlement.repay` routes
payment through `BookHook`: zero counterparty debits the active account only,
while an account counterparty receives the same liability quantity. Zero debt
skips booking and invokes no account hooks or account-format checks. The asset
leg remains unsettled.
A subsequent `settle` processes the remaining asset leg.

Host implementations choose a position-fulfillment model: hosts that maintain
account balances use `settle`, while hosts without their own account balance
ledger implement `realize` and return the fulfilled position to the caller.
A production host is not intended to expose both as alternative routes for the
same operation. `Settlement` provides reusable mechanics for ledger hosts;
producers supply final quantities with fees already handled. The combined
realize/settle test host exercises both interfaces for integration coverage.

Host payers and host counterparties follow the same exact-quantity and limit
rules as other accounts. Self-exchanges leave balances unchanged but still
require funding for each debit before its matching credit. Matching assets are
not netted, so incoming assets cannot fund the initial liability debit.

For realization, the command calls `realize(account, position)` for each POSITION
and outputs the result. Input must be empty. To protect the returned quantities
and denominations, compose `realize -> checkPosition -> settle` in one atomic
pipeline. A failed check rolls back realization and any earlier effects. The
check is optional. The realization hook must preserve asset and liability
identifiers and return counterparty zero after fulfillment.

The QUOTE schema remains available independently:

```txt
#quote { bytes32 asset, uint amount, bytes32 liability, uint debt }
```

A QUOTE describes asset and liability quantities using four full-width words,
ordered as `asset, amount, liability, debt`, matching the first four fields of
POSITION. Its payload is 128 bytes, or 136 bytes including the header. It decodes
into a distinct `Quote` struct exported through `Core.sol`, `Codec.sol`, and
`Commands.sol`. Counterparty is not part of the quote. It is not live position
state; the consuming operation determines how its quantities are interpreted.

Cursor and execution helpers decode quotes with `unpackQuoteValue()` or return
`(asset, amount, liability, debt)` from `unpackQuote()`. Scalar quote writers and
factories use the same order; structured writers accept a `Quote`. QUOTE remains
a separate schema whose interpretation is defined by its consumer; it is not
accepted by `checkPosition` or the position-constraints expectation helpers.

The former three-word `asset, liability, limits` QUOTE format is invalid.

Position acceptance constraints use a separate schema:

```txt
#positionConstraints { bytes32 asset, uint amount, bytes32 liability, uint debt }
```

POSITION_CONSTRAINTS has a 128-byte payload (136 including the header), with the same
word order as QUOTE but a distinct key. Offchain callers encode these constraints.
`unpackPositionConstraints` readers return a `PositionConstraints` struct with
`(asset, amount, liability, debt)` from calldata, cursors, memory, or execution
input. There is no onchain writer, factory, or execution-output helper.

`checkPosition` and the `expectPositionConstraints` helpers require exact asset and
liability identifiers, then check `position.amount >= constraints.amount` and
`position.debt <= constraints.debt`. The constraint `amount` is the minimum asset
receipt; `debt` is the maximum liability payment. Both bounds are inclusive
full-width uint256 values with no sentinels. They constrain separate quantities,
so `amount` may exceed `debt`. Counterparty is not part of these constraints; authorization
and backing remain separate responsibilities. Codecs preserve values without
applying the comparisons.

`Blocks.expectPositionConstraints(abs, position)` performs the same checks directly
against calldata without unpacking its payload. The caller
must bound the complete block. It validates the POSITION_CONSTRAINTS header first
(`InvalidBlock`), then identifiers (`UnexpectedValue`), then quantity bounds
(`OutOfRange`). It does not advance a cursor or check the counterparty.
`Executions.expectPositionConstraints(exec, position)` bounds and consumes one
POSITION_CONSTRAINTS input before delegating to it.

Realize consumes empty input. Code checking a Rootzero-backed result
must separately require zero on the resulting position's counterparty. Failed
comparisons revert the enclosing call and its earlier changes.

`checkPosition` (`CheckPosition` in `commands/Position.sol`) accepts POSITION state and
one POSITION_CONSTRAINTS input per position, checks exact asset and liability identifiers and
inclusive minimum amount / maximum debt, and returns each position unchanged.
Empty state with empty input is valid; missing, extra, malformed, or failing
constraints revert the call. It does not check counterparty authorization or backing.
Place it after the transformations whose output should satisfy the limits, for
example `transform → checkPosition → settle`, within the same atomic pipeline.

`ExecuteCheckPosition` adds internal memory-state execution for the same command
ID. It validates POSITION blocks in memory directly against POSITION_CONSTRAINTS blocks in
calldata using assembly, without unpacking structs or copying output. It returns
the original state buffer and any assigned native budget unchanged. Hosts route
`checkPositionId()` to `executeCheckPosition(account, state, input, value)` in their
local execution dispatcher. The normal external command uses the standard
execution callback and emits unchanged positions through the output writer.

This representation supports ordinary forward transformations as well as
backward composition. For example, an exact-output route can carry its desired
asset while successive hops replace the upstream liability:

```txt
position(C, 100, C, 100, 0)
→ position(C, 100, B, 50, 0)
→ position(C, 100, A, 25, 0)
→ settle()
```

“Backward” describes how requirements are composed from the desired result
toward the source. Pipeline execution is not reversed: STEP blocks always run
forward in their encoded order. Exact-output routing is only an example;
borrowing, refinancing, collateral transformation, callback obligations,
cross-host claims, fees, and netting can use the same position state.

## Field Aliases

Standard block aliases come from the protocol catalog; custom block aliases may
be published in `#schema` annotations. Field aliases are presentation metadata
for tooling. They do not change payload layout or runtime keys.

```txt
#account as recipient
{ uint target, uint value, #bytes as payload }
```

Field aliases may be used on any block item, including child blocks and prime
items.

Child blocks are schema references:

```txt
{ uint handler, uint value, bytes32 key, #bytes as witness }
```

Alias resolution is context-dependent. A consumer resolves `#context` from the
standard catalog and may resolve custom aliases from app-specific annotations
or another active schema context. Custom parents should define nested custom
blocks from the bottom up and reference them by alias. Consumers should reject
schemas with unresolved aliases. The runtime encoding is still an embedded
child block with the referenced key and layout.

## Field Paths

Field names and aliases may use dotted paths for offchain projection. A dotted
path does not change the block key, payload bytes, payload length, cursor
behavior, or any onchain validation. It is metadata only.

```txt
{ uint dst.portal, uint dst.resources, #bytes as dst.payload }
```

This has the same runtime layout as:

```txt
{ uint portal, uint resources, #bytes as payload }
```

Offchain tooling may decode the dotted form into a nested object:

```ts
{
  dst: {
    portal,
    resources,
    payload
  }
}
```

Encoding and decoding must still follow schema declaration order, not object
property order. Fields with the same path prefix do not need to be contiguous,
although contiguous fields are easier to read when they represent one logical
object.

Tooling should reject duplicate full paths and prefix/value collisions:

```txt
uint dst.portal, uint dst.portal    // duplicate path
uint dst, uint dst.portal           // prefix/value collision
```

The same rule applies to field aliases:

```txt
{ uint target, uint value, #bytes as calldata.payload }
#account as recipient.account
```

## Presentation Order

An item may use `at N` to select its zero-based position in the offchain
presentation of its enclosing item sequence. This is projection metadata only:
it does not change wire order, payload offsets, block keys, encoding, or onchain
decoding.

```txt
{
  uint32 fee,
  int32 tickSpacing,
  uint hook,
  #bytes as hookData,
  #position at 0,
  many #swapHop
}
```

The wire order remains:

```txt
fee, tickSpacing, hook, hookData, position, swapHop
```

The offchain presentation order is:

```txt
position, fee, tickSpacing, hook, hookData, swapHop
```

To construct the presentation order, tooling first reserves every position
named by `at`, then fills the remaining positions with unannotated items in
their original declaration order. This permits one item to be repositioned
without annotating every sibling. Multiple `at` annotations may be used when
more positions need to be fixed explicitly.

An `at` position must be less than the number of sibling items, and two siblings
must not select the same position. Tooling must reject duplicate or out-of-range
positions. An item without `at` retains its order relative to the other
unannotated items. Each nested schema body applies presentation ordering
independently; a `many` declaration occupies one position in its enclosing body.

`at` follows the complete item, including any field alias:

```txt
uint amount at 0
#bytes as hookData at 2
#account as recipient at 1
many #swapHop at 3
```

Encoders and decoders must always process items in declaration order. Consumers
may apply `at` only after decoding when constructing an offchain object, tuple,
table, or user interface.

## Field Types

Supported field types are chain-neutral:

```txt
uint, uint8, uint16, uint32, uint64, uint128, uint256
int, int8, int16, int32, int64, int128, int256
bool
bytes1 through bytes32
```

`uint` means `uint256`; `int` means `int256`. Other integer widths, unsized
`bytes`, `string`, and array syntax are not part of the core schema DSL.

Restricting fixed bytes to the power-of-two widths `bytes1`, `bytes2`,
`bytes4`, `bytes8`, `bytes16`, and `bytes32` is under consideration, but has
not been decided. Until that decision is made, the schema DSL continues to
allow every `bytesN` width from 1 through 32.

Integers are encoded big-endian. Signed integers use two's-complement encoding
for their declared width. `bool` is one byte: `0x00` for false and `0x01` for
true. `bytesN` values are encoded as exactly `N` bytes with no padding.

## Chain Resources

Fields named `portal` identify destination portal hosts. By convention, the
value is the host ID of the destination portal implementation. Core encoding
and dispatch pass the value through unchanged; transport hooks are responsible
for any validation or route resolution they require.

Fields named `resources` are opaque packed chain-specific words, not plain
native values. A portal adapter interprets them for the destination runtime.
Different runtimes may pack these words differently, but a given runtime must
use one stable format everywhere. For EVM chains, the low 128 bits are native
value / endowment in wei; higher bits are reserved for execution resources such
as gas. EVM code must call `useResourceValue` to extract and spend the value lane.

STEP, CALL, and RECOVER blocks use full-width `uint value` drawn from the shared
native-value budget. CALL assigns value to a local call, and RECOVER assigns it
to a recovery-handler invocation. Neither truncates value to 128 bits. Recovery
hooks debit the value with `useValue` or `rawCall`, preserving returned credit.
DISPATCH is the only standard block carrying packed `resources`; custom relay
input may also carry destination resources for a transport adapter.

CALL and RECOVER retain their block keys and byte layouts, but their second word
now means native value. Migrate older inputs that packed resource metadata into
the high bits; those bits now contribute to the requested value and budget check.

## Protocol IDs

Account, asset, and node ID fields use one 32-byte convention:

- first byte `0x00`: null/unset ID.
- first byte `0x01`: Rootzero-native structured ID.
- first byte `0x02`: opaque ID, encoded as
  `[0x02][category][subtype][bytes29(hash)]`. The full
  preimage must come from a lookup table or witness data when native metadata is
  needed.
- first byte `0x03`: EVM structured ID. The value may be deconstructed
  according to its EVM layout.

Opaque preimages use `[formatHash][category][subtype][payload...]`; `0x01`
means keccak256. Category and subtype are included in the hash and copied into
the ID. The remaining bytes are host/domain-specific until the protocol
standardizes a fuller preimage payload format.

Opaque IDs carry the same protocol category and subtype taxonomy as structured
IDs, allowing their role to be validated without external context. Their native
identity and metadata still require lookup or witness data.

Asset subtypes are `0x00` for a representation's default asset, `Derived = 0x01`,
`Virtual = 0x02`, and `Erc20 = 0x03`. Derived and Virtual are reserved taxonomy
values without dedicated helpers or standardized subtype-specific payloads.

## Identifiers

Block aliases and unqualified schema names use lower camelCase ASCII
identifiers. Field names, field aliases, and qualified byte-content schema
names use one or more lower camelCase path segments separated by dots:

```txt
[a-z][a-zA-Z0-9]*
[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)*
```

Invalid examples:

```txt
AssetAmount
asset_meta
asset-meta
0account
asset.
.asset
```

Reserved words include `many`, `as`, `at`, all field type names, and the
reserved block aliases `bytes` and `list`. For dotted paths, reserved words are
invalid in any path segment.

## Reserved Blocks

- `#bytes`: raw dynamic bytes, written without a body
- `#string`: UTF-8 string bytes, written without a body
- `#list`: generic list wrapper emitted by nested `many`

Custom input shapes should define their own context-local block spec and publish
it with a `#schema` annotation. Endpoint contracts can use `schema(...)` to
construct and publish that spec:

```solidity
uint input = schema("{ bytes32 asset, uint amount }", 1, 64, 64, 64);
```

The body string comes first in every overload:

```solidity
schema(body, spec);
schema(body, key, size);
schema(body, key, min, max, hint);
```

Use different numeric keys when a host needs more than one local block key. The
key can also be a selector or any other `bytes4` value that is unique in the
context where it is used. The numeric arguments after the key are the minimum,
maximum, and allocation hint payload sizes. The optional `name:` prefix names
the block; the remainder of the schema string describes its payload body.

## Standard Blocks

The complete canonical name/body catalog lives in `contracts/codec/Schema.sol`;
the corresponding keys and packed specifications live in `Keys.sol` and
`Specs.sol`. These names are intrinsic standard metadata and need not be emitted
as a prefix in `#schema.body`:

```txt
bytes                ""
string               ""
list                 ""
evm                  ""
node                 uint node
entity               uint entity
account              bytes32 account
asset                bytes32 asset
status               uint code
amount               uint amount
assetAmount          bytes32 asset, uint amount
balance              bytes32 asset, uint amount
debt                 bytes32 liability, uint debt
accountAsset         bytes32 account, bytes32 asset
assetLiability       bytes32 asset, bytes32 liability
hostAsset            uint host, bytes32 asset
bootstrap            uint budget, many #assetAmount as balances
allocation           uint host, bytes32 asset, uint amount
allowance            uint host, bytes32 asset, uint amount
custody              uint host, bytes32 asset, uint amount
accountBalance       bytes32 account, bytes32 asset, uint amount
accountAmount        bytes32 account, bytes32 asset, uint amount
hostAmount           uint host, bytes32 asset, uint amount
hostAccountAsset     uint host, bytes32 account, bytes32 asset
limits               uint limits
balanceConstraints   bytes32 asset, uint min, uint max
positionConstraints  bytes32 asset, uint amount, bytes32 liability, uint debt
quote                bytes32 asset, uint amount, bytes32 liability, uint debt
position             bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty
booking              bytes32 from, bytes32 to, bytes32 liability, uint debt, bytes32 asset, uint amount
transaction          bytes32 from, bytes32 to, bytes32 asset, uint amount
hostAccountAmount    uint host, bytes32 account, bytes32 asset, uint amount
step                 uint cmd, uint value, #input
swap                 bytes32 asset, uint amount, many #asset as hops
call                 uint target, uint value, #bytes as payload
relay                #input, #bytes as steps
dispatch             uint portal, uint resources, #bytes as payload
context              bytes32 account, #state, #input
recover              uint handler, uint value, bytes32 key, #bytes as witness
annotation           uint entity, #bytes as data
counterparty         bytes32 account
groups               #string as description
schema               uint spec, #string as body
```

`#amount` contains a single full-width quantity; its consumer defines the asset
or unit. `#assetAmount` contains both an asset identifier and its quantity.
Commands and ports that accept a caller-selected asset use `#assetAmount`.
These are input/value blocks, distinct from live `#balance` state.

The former two-word `#amount` layout is replaced by `#assetAmount`. Old encoded
inputs must be re-encoded with the new key; scalar `#amount` accepts exactly
32 payload bytes and rejects the former 64-byte payload. Decode historical
deployments using the schemas applicable to those deployments.

`#swap` contains an asset and amount followed by a LIST of ASSET blocks.
`swapExactIn` interprets the fixed fields as the input liability and exact debt,
with hops in forward order ending at the output asset. `swapExactOut` interprets
them as the desired output asset and amount, with hops in reverse order ending
at the input asset. Hops excludes the asset named in the fixed fields: A ? B ? C
is encoded as A with [B, C] for exact-in, or C with [B, A] for exact-out.
The codec validates the outer container and final LIST framing. The commands
accept empty routes, validate each ASSET block and invoke one scalar hook
per hop. Exact-in carries the returned amount forward; exact-out carries the
returned debt backward. Hooks validate amounts and asset pairs and settle
intermediate assets internally. Each command produces one aggregate Position
with its immutable Counterparty; position constraints remain separate commands.
Empty routes invoke no hook and return a Position with equal asset/liability and
amount/debt. The position is logged normally; settlement may still book both legs.

`#entity` carries one full-width identifier, matching the `uint entity` field in
annotations. It is distinct from `#node` and `#asset`; the codec validates the
exact 32-byte payload without restricting the identifier's kind or rejecting zero.

`GetBalance` is the only built-in query. Custom queries can use `QueryBase` for
specific direct-read requirements; normal application reads come from the indexer.

### Host Accounts

The EVM account subtypes are `Admin = 0x01`, `Host = 0x02`, and `User = 0x03`.
`Layout.Host` is also the host node subtype; categories distinguish the two IDs.
A host account encodes `[0x03010200][uint32 chainid][zero:4][address:20]`.
It is deterministic and chain-bound, with no registration required.

`Accounts.toHost(address)` uses the current chain. `Accounts.toHost(uint node)`
checks the EVM host node prefix and translates its chain and address to the account
layout. The latter preserves remote chain IDs. Like other account encoders, these
functions can encode a zero address; `Accounts.host` rejects it. `Accounts.isHost`
checks only the full prefix, and `Accounts.host` does not require a local chain.
Neither checks deployed code or grants authority over balances.

A host account counterparty may be settled through account debit/credit hooks
on any host where it has sufficient balances, or realized by its own host.
The subtype does not dictate routing. Deriving a host account does not invoke
that host or make it a trusted peer.

## Pipeline context

The standard `#pipeline` block has the schema:

```text
bytes32 account, uint budget
```

Its key is `bytes4(keccak256("#pipeline"))`. Both fields are full 32-byte words:
64 payload bytes, 72 bytes including the header. budget is this invocation's initial
native-value budget (wei on EVM), not necessarily msg.value and not an additive
funding record across nested calls.
There is no deadline; expiry enforcement belongs to the invoking entrypoint.

`Keys.Pipeline`, `Schemas.Pipeline`, `Specs.Pipeline`, `Headers.Pipeline` and
`Sizes.Pipeline` expose the layout. `Encoder.createPipeline`/`writePipeline`
encode it; `Blocks.unpackPipeline` validates and decodes it. Executions provides
`outputPipeline` and `unpackPipeline`.

Pipeline execution emits no entry event. The former Pipeline category (6) is
reserved and is not reused. Execution records carry their own account context;
Balance records carry actual balances. The standard block codecs above remain
available for explicit block data, independently of the removed event.

This replaces the Rooted schema and helper APIs and removes RootedEvent and its
public export. The new key prevents confusing the two-word Pipeline layout with
the historical three-word Rooted layout. Historical logs retain their original decoder.

### Event output containers and capacity

`Output`, like `State` and `Input`, is an unbounded block-stream container with
an empty schema body and a 128-byte payload allocation hint. Its key is
`bytes4(keccak256("#output"))`. Logging wraps the entire finalized output in this
block; return values remain unwrapped.

Encoder reserves one owned 32-byte word before the bytes length on allocation
and every growth. It is separate from logical capacity, length, cursor offsets,
and trailing scratch. Descriptor allocation hints and growth thresholds are
unchanged: filling an exact initial capacity does not resize the buffer.
Execution logging reserves its category, endpoint, account and selected lane
headers inside the shared writer. `Logs.execution` emits that initialized range
without copying. `finish` then exposes only the output region as returned bytes.
Resolve addresses after growth; the output-start offset survives buffer resizing.

### Account balances and requested amounts

`#accountBalance { bytes32 account, bytes32 asset, uint amount }` reports an actual
balance, including zero. getBalance returns this schema. Its payload is 96 bytes;
the complete block is 104 bytes. `Logs.balance` instead emits a fixed 97-byte
Balance category record with account, asset and actual amount, without a block wrapper.

`#accountAmount` retains the same field layout with a different key and meaning:
it carries requested amounts, including credit/debit port inputs. Do not interpret
these requests as resulting balances. Existing getBalance consumers must migrate
to the AccountBalance key.

### Bootstrap funding request

BOOTSTRAP contains a full-width budget followed by one LIST of ASSET_AMOUNT
blocks. Its minimum payload is 40 bytes; the complete block is 48 + 72 * count
bytes. Budget is the minimum native credit remaining after requested balances
are funded. ExecuteBootstrap accepts exactly one outer block, including an empty
list for budget-only funding, and produces one BALANCE per inner item. The total
requested chainAsset amount must fit uint256; it is accumulated with checked
arithmetic before assigned value is applied.

This replaces the former fixed `(asset, amount, budget)` payload under the same
key. Clients and indexers must select the schema for the deployed version;
old encodings are not accepted by the new command.
