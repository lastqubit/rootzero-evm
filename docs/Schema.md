# Schema

Rootzero input and response data is encoded as a stream of typed blocks. A
schema string describes the payload body for discovery events and tooling; the
runtime block key is the compact type tag that identifies that payload layout in
the active schema context. The block alias comes from the protocol's standard
catalog or an explicit schema annotation name; it is not part of the payload
schema string.

## Wire Format

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
and therefore know, for example, that the key derived from `#amount` is named
`amount` and has the body `{ bytes32 asset, uint amount }`. This does not depend
on a host emitting a named schema annotation.

If an emitted `#schema` block has `name == bytes32(0)` and its key is standard,
tooling uses that key's canonical standard alias. A zero name on a nonstandard
key remains unnamed. An explicit nonzero name is still required for qualified
bindings such as `relay.input`.

Custom block keys do not have to be keccak-derived. They
are opaque `bytes4` tags and only need to be unique in the context where they are
used. A host can publish the meaning of a custom key as an annotation:

```solidity
event Annotation(uint indexed entity, bytes data);
#schema { uint spec, #string as body, bytes32 name }
```

Annotation merge behavior is defined by the annotation block type rather than
by the `Annotation` event. A `#schema` annotation is identified by its entity
and the block key encoded in `spec`: distinct keys accumulate, while the latest
trusted claim for the same key replaces the earlier one. Other annotation types
may define additive, historical, or explicitly revocable behavior instead.

The standard `#action { uint action }` annotation assigns one primary semantic
action to an entity. The latest trusted value replaces the previous value, and
`Actions.None` clears the classification.

The standard `#counterparty { bytes32 account }` annotation assigns a counterparty
account to an entity such as a command or asset. The latest trusted value replaces
the previous account, and zero identifies Rootzero. Host accounts use the same
representation as in POSITION. The annotation identifies the counterparty, not
whether to settle or realize it. Like other annotation helpers, it encodes the
claim without validating either ID; consumers apply type and trust policy.

The standard `#executionCost { uint base, uint batch }` annotation describes a
command's estimated execution cost in destination-local execution units. Its
payload is exactly 64 bytes. Estimate cost as `base + batch * batchCount`, where
a batch is one logical group processed by the command, including all constituent
blocks. Pipeline and transport overhead are separate. Estimates are advisory;
missing annotations or unknown batch counts mean unknown cost. The latest
trusted annotation replaces both fields; zero values are valid estimates.
`ExecutionCost.executionCost(entity, base, batch)` publishes the annotation.

For example, a host-specific payment block can use a small literal, the command
selector, or any other chosen `bytes4` value as long as that key is not
overloaded in the relevant host/schema context.

## Block Syntax

A block definition has an event alias and a schema body. A schema body is one
of these forms:

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
alias:  amount
schema: bytes32 asset, uint amount
also valid: { bytes32 asset, uint amount }
```

Consumers must remove one matching pair of outer braces, when present, before
parsing the item sequence. Only commas outside alias-list parentheses separate
sibling items. Unmatched braces and additional
outer brace layers are invalid.

A block body can reference another block alias as a child item with `#`:

```txt
{ bytes32 account, #bytes as state, #bytes as input }
```

The empty schema string `""` means the block has no structured payload. This is
used for raw dynamic blocks such as `#bytes`.

Every block key also has an empty wire form consisting of its header with a
zero payload length. Empty blocks are structurally present but contain no body
to decode. Existing semantic decoders remain strict: for example,
`unpackBalance` rejects an empty `#balance` unless its caller detects and
consumes the empty form first.

When a parent block is non-empty, every child block declared by its schema is
represented by a header in declaration order. A child without a value uses its
empty form rather than being omitted. An empty parent is terminal, so its body
and nested child headers are not present.

A structured schema body is a comma-separated list of items. Order is
significant.

```txt
{ #amount, maybe #account as recipient }
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
one alias. Use the expanded form for `maybe`, `many`, or per-item `at` modifiers.

For example, this is valid alongside ordinary sibling items:

```txt
uint id, #bytes as (source.payload, destination.payload), #account as owner
```

Commas inside the parentheses separate aliases, not schema items. After
expansion, all ordinary sibling validation and presentation rules apply.

## Payload Layout

A block payload encodes schema items in declaration order. Fixed fields are
packed inline, and zero or more child blocks are embedded directly at their
declared positions. Because every child block carries its own header and payload
length, fixed fields may appear before, after, or between child blocks.

```txt
{ uint target, uint resources, #bytes as payload }
{ bytes32 account, #bytes as state, #bytes as input }
{ uint spec, #string as body, bytes32 name }
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
relay { #bytes as input, #bytes as steps }
```

A relay implementation can publish its transport-specific input shape with the
existing schema annotation helper:

```solidity
schema(
    inputSpec,
    "uint portal, uint resources",
    bytes32("relay.input")
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

Empty-value acceptance and repeated items are expressed with prefix keywords:

```txt
#balance
maybe #balance
many #balance
```

- no prefix: one required item whose ordinary value rules determine whether its
  payload may be empty
- `maybe`: one required header whose payload may be empty
- `many`: one required list header containing zero or more repeated items

These modifiers are offchain hints describing the forms accepted by the
onchain consumer; they do not change runtime validation. `#bytes`, `#string`,
and lists accept empty payloads as ordinary values, so applying `maybe` to them
has no additional meaning and tooling may normalize it away.

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
schema name: zero (unnamed)
schema body: #accountAmount as (debit, credit)
expanded:    #accountAmount as debit, #accountAmount as credit
wire:        [0x00000001][208][ACCOUNT_AMOUNT debit][ACCOUNT_AMOUNT credit]
```

The parent schema identifies one complete operation; batching repeats that parent.
This remains available for custom compositions, but `portBook` uses a flat stream
instead: its descriptor declares ACCOUNT_AMOUNT input and its `#groups` annotation
on the port ID is `#input as (debit, credit)`. Each pair occupies 208 bytes with no
parent header. Two bounded reads enforce complete pairs before calling the hook;
a missing second block or malformed header reverts the whole batch.

## Endpoint Lanes

Endpoint descriptors identify each lane with a top-level block key. Each block
represents one operation; fixed compositions use a custom parent block.
Solidity endpoint helpers accept specs such as `Specs.Amount`, while
`Specs.Empty` declares an absent lane. There is no stride or group multiplier.

The packed descriptor uses this layout, from most to least significant byte:

```txt
[state key:4][input key:4][output key:4][source key:4]
[source block size:4][output block size:4][source shift:1][lanes:1][reserved:5][flags:1]
```

Endpoint loop grouping is described separately by a `#groups` annotation on the
endpoint ID. Its payload schema is `#string as description`. For example:

```txt
#state as (debit, credit), #output as (receipt, change)
```

This is a dedicated annotation language, not a block payload schema. Only
`#state`, `#input`, and `#output` are lane references; each resolves to the
corresponding descriptor schema. An entry is a lane reference followed by `as`
and a parenthesized list of at least two aliases. Commas outside parentheses
separate entries. Each lane may appear once. Aliases use the ordinary schema
alias-path rules; duplicate or colliding aliases within a lane are invalid.
Alias order describes consecutive blocks within one loop iteration. No wrapper
or extra block header is added, and no global schema aliases are introduced.

Only grouped lanes are listed; omitted lanes have no grouping hint. Descriptor
schemas take precedence: entries for empty lanes are ignored and cannot create
blocks. Group counts are implied by the alias lists, not stored in descriptors.
Annotations affect neither decoding, allocation, nor runtime enforcement;
commands may separately call `scaleOutput` to adjust their allocation hints.
Indexers can use the description to interpret repeated loop groups; incompatible
streams should be reported as inconsistent hints, not reinterpreted as new encoding.

`GroupsAnnot.annotateGroups(endpointId, description)` publishes the string without
on-chain syntax validation. The latest annotation from a trusted emitter replaces
the previous whole description; an empty string clears the hints. Invalid selected
annotations should be reported by tooling rather than silently falling back to an
older description. Trust remains the consumer's responsibility.

The allocation source is declared state when present, otherwise input. Its shift
is 64 for state and zero for input or no source. Block sizes include the header.
The lanes byte precomputes state presence in bit 0 and input presence in bit 1.
Opening copies it into decoder bits 128-135; input-only opening copies only bit 1.

Solidity code constructs this metadata with `Executions.describe`. The same
library initializes an `Execution` through `exec.open` or `exec.openInput`;
their packed state/input cursors are an internal execution representation and
are not returned as general-purpose cursors. `exec.open` initializes the
command account and an explicit native-value budget together with both sources
and the output writer. Input-only endpoints use `exec.openInput`, which accepts
an explicit budget but no command account. Passing the budget explicitly keeps
both opening helpers pure and supports callers that forward an existing budget.
Both in-place helpers expect a newly allocated or otherwise empty `Execution`.

Standalone `Cur` values use a separate compact generic cursor containing only
an absolute current position (bits 0-31), absolute exclusive end (bits 32-63),
and flags (bits 64-71). They do not retain a source offset or expose a relative `decode` view. Low-level
`seek`, `expect`, `slice`, `raw`, `peek`, `hasAt`, and `find` positions are
absolute calldata positions; `past` and `find` also return absolute positions.
The cursor is forward-only, so explicit ranges must remain within its unread
`[position, end)` region. Buffer writers reuse the layout with origin zero,
making their current position a write offset and their end a logical capacity.

Flag bits 0 and 1 are the protocol-defined `funded` and `admin` flags. Bit 7 is
the protocol-defined `handoff` flag, bit 6 is reserved for endpoint-defined
behavior, and bits 2 through 5 remain reserved for future protocol flags.

Execution packs input current/end in bits 0-63 and state current/end in bits
64-127. Bits 128 and 129 record whether state and input are declared, preserving
EMPTY-lane behavior for raw forwarding. Buffer writers use only bits 0-63.

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

An endpoint may accept the empty form of its prime block as a per-operation
marker. The header remains present, so empty prime blocks still participate in
run counting and batching.

Execution cursor opening wraps the supplied state and input calldata without
validating their descriptor keys. Those fields remain discovery
metadata. When output is declared, writer pre-sizing may count the consecutive
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
`takeRawState`, or reverting. Descriptor metadata alone does not reject a source;
a command that leaves supplied state unread rejects it when closing. Ordinary
typed consumption validates blocks against the type requested by the command.
Raw forwarding deliberately trusts the command and does not validate the
forwarded source against descriptor metadata.

## Live Pipeline State

STEP command IDs use subtype `0x03` and copy their descriptor flags into the
last byte of the ID type field. Flag bit 7 and the envelope
`relay { #bytes as input, #bytes as steps }` identify handoff commands.
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
Callers do not select or switch an active decoder source.

Standalone `Cur` decoders remain source-agnostic because they represent one
explicit byte region. `takeRawState` is the deliberate execution exception: it
may forward unread state without interpreting or validating its block types,
but marks that complete region consumed. `takeRawBalances` validates every
remaining block as BALANCE before returning the original calldata stream;
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
settlement and realization hooks validate the counterparty.
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
`Memory.unpackPositionValue` to decode the same struct. The hooks are `settle(account, position)` and
`settle(account, position, funds)` for funded settlement. Commands leave counterparty validation and authorization to the hook.
`Settlement` implements the unfunded hook. Producers enforce limits before
emitting positions; settlement books zero-counterparty positions on the active
account.
Nonzero counterparties are passed unchanged to the account hooks when transferring
the exact debt followed by the exact asset amount. Authorization remains with
trusted position producers and host account hooks. Account format checks belong
to `debitAccount` and `creditAccount`; a custom `BookHook` that bypasses those
hooks must apply its own account policy. Empty exchanges skip the account hooks
and do not validate the counterparty. Funded settlement still uses
the host's separate hook with the same exact-quantity requirements.

`settle` consumes POSITION state with empty input and output. `ExecuteSettle`
provides the same settlement hook for memory-backed
pipeline state. For zero counterparties it calls
`book(account, account, asset, amount, liability, debt)`. `BookHook` remains
defined in `core/Settlement.sol`; its default implementation debits the exact
liability amount and then credits the exact asset amount. Zero amounts skip
account hooks, and any failure reverts the whole operation.

The former `book` command is removed. `settle` accepts account counterparties and
applies final quantities without checking limits; producers must enforce their
quantity constraints. Callers that require an already-realized
position must explicitly check counterparty zero, for example with
`Positions.requireQuoted` and a quote whose counterparty is zero. A trusted
realization hook must return counterparty zero before handing the result onward.

The same `BookHook` is used directly by `portBook` and settlement for its
exact transfers. The `BookHook` signature is
`book(from, to, asset, amount, liability, debt)`. It must apply both exact legs
or revert, skip zero-amount legs, and preserve debit-first funding requirements
even when accounts or assets match. It does not net legs or interpret a zero
account as an absent side. Callers encode zero debt or amount to omit a leg.
`portBook` decodes both input legs
before calling the hook, so malformed credit data is rejected before debiting.

`realize` passes the complete position to its hook, which validates its host account
counterparty and fulfills the obligation before returning counterparty zero.
The command takes one LIMITS input per position and checks the returned quantities
with `Positions.requireLimits(position, limits)`. Identifier and counterparty correctness belong to the hook.

### Position Transformations

The position layout is flat, with both sides followed by the counterparty;
it is not a nested Solidity struct. The asset side represents
value acquired or controlled, and the liability side represents value owed or
required. Commands may preserve or replace either side and return a new
position. The terminal `settle` command exchanges with an account counterparty
or limit-checks a zero-counterparty booking. Positions, including
liability-only positions, are transient state; rewriting them does not by itself create,
discharge, or replace an obligation persisted by a host or external protocol.
The responsible command hook must perform or verify those effects. A command
must not ignore supplied position state: it must explicitly consume,
transform, forward, or reject it, so an obligation cannot disappear
accidentally.

`settle` and `settlePayable` consume positions, including liability-only
positions, and return empty state. To repay, use a POSITION with zero asset and
amount. There are no separate repayment commands or repayment hooks. Hosts
implement settlement, which routes the liability transfer through
`BookHook.book`. A position with an asset side also settles that side instead
of returning a BALANCE block.
The single `realize` command calls one hook:

```solidity
function realize(bytes32 account, Position memory position) internal virtual returns (Position memory);
```

The hook fulfills both sides in their existing asset and liability denominations.
It validates the counterparty, chooses its internal operation order, and returns
the complete realized position with counterparty zero. It must fulfill the entire
obligation or revert: no source remainder is emitted, and fees or rounding must
not silently discard debt. The command checks the returned quantities against
the paired LIMITS input; identifier and counterparty correctness remain the
hook's responsibility.

The standalone `#limits { uint limits }` schema carries only quantity
constraints in one packed word: the high 128 bits are the inclusive minimum net
asset amount, and the low 128 bits are the inclusive maximum total liability debt,
including fees. Its payload is 32 bytes (40 with the header). Both lanes are
literal bounds: `type(uint128).max` is a cap, not an unlimited sentinel.
It identifies no asset, liability, or counterparty. Position quantities remain
full-width uints; output amounts may exceed 128 bits, but debt cannot exceed the cap.

Pack with `(minAmount << 128) | maxDebt` after ensuring both inputs fit uint128.
`unpackLimits` returns the packed uint from calldata, cursor, execution, or memory
sources. Writers and execution outputs accept that same word. Codec helpers
validate the block header and preserve the value without enforcing quantities.
`Positions.requireLimits(position, limits)` checks the inclusive bounds and
reverts with `OutOfRange`; it does not validate identifiers or counterparties.

`Blocks.requireLimits(abs, amount, debt)` checks the LIMITS header and compares
full-width quantities directly against its calldata payload. The caller must bound
the complete block. `Executions.requireLimits(exec, amount, debt)` bounds and
consumes one LIMITS input before delegating to it. `Realize` uses this helper on
the returned position, without unpacking limits into a Solidity value.

`Blocks.unpackLimitedPosition(pos, lim)` checks both exact block
headers, compares the position quantities against the packed limits directly in
calldata, then returns a `Position` struct. Its caller must establish bounds for
both complete blocks. It does not advance streams or validate identifiers.
`Executions.unpackLimitedPosition(exec)` bounds and consumes one POSITION from
state and one LIMITS from input, then delegates to this helper.
`Memory.unpackLimitedPosition(pos, lim)` performs the same checks
with the POSITION in memory and LIMITS in calldata, returning an independent
copy via `mcopy`. Both complete blocks must be in bounds. These limited-position
helpers remain available for commands that need paired quantity checks.

`settle` and `settlePayable` consume any number of POSITION blocks with empty
input. `ExecuteSettle` rejects nonempty input with `UnexpectedInput`, establishes
fixed-size memory bounds, and iterates the position stream. Partial blocks revert
with `InvalidBlock` when establishing bounds. The settlement hook validates and
authorizes the counterparty. Producers enforce `net amount >= limits >> 128` and
`total debt <= uint128(limits)` on their final outputs where those limits apply.
`Realize` already checks its returned position against its paired LIMITS input.
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
It publishes `Actions.Repay` (82). The unfunded `RepayHook` must satisfy the
complete exact debt or revert and must not mutate its position argument; the
command clears debt only after the hook succeeds. `Settlement.repay` routes
payment through `BookHook`: zero counterparty debits the active account only,
while an account counterparty receives the same liability quantity. Zero debt
skips booking and account validation. The asset leg remains unsettled.
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

For realization, each POSITION is paired with one LIMITS input. The command calls
`realize(account, position)`, then `Positions.requireLimits(result, exec.unpackLimits())` before
outputting the result. A failed quantity check or malformed LIMITS input reverts
all hook changes. The hook must preserve asset and liability identifiers and
return counterparty zero after fulfillment; the command does not check those fields.

The QUOTE schema remains available independently:

```txt
#quote { bytes32 asset, bytes32 liability, bytes32 counterparty, uint limits }
```

A QUOTE constrains the resulting position: `asset`, `liability`, and `counterparty` must match exactly,
`limits` packs the inclusive minimum asset output into its high 128 bits and
the inclusive maximum debt into its low 128 bits. Both lanes are literal bounds,
including `type(uint128).max`; there is no unlimited-debt sentinel. Actual asset
output may exceed 128 bits, but quoted debt cannot exceed the cap.
The quote has four words (128 payload bytes, 136 bytes including the header).
It decodes into a distinct `Quote` struct exported through `Core.sol` and
`Codec.sol`; positions retain their full-width actual quantities.
Counterparty zero requires Rootzero backing;
it is not a wildcard. It is an input schema, not live position state.

Cursor and execution helpers decode quotes with `unpackQuoteValue()`. Callers
can use `Positions.requireQuoted(position, quote)`, exported through `Utils.sol`,
to enforce exact identifiers and counterparty, then check the inclusive quantity
bounds through `Positions.requireLimits(position, quote.limits)`.
Realize does not consume QUOTE input. Code that independently validates a
Rootzero-backed result against a quote must require counterparty zero in that
quote. Failed comparisons revert the enclosing call and its earlier changes.

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
maybe #account as recipient
{ uint target, uint resources, #bytes as payload }
```

Field aliases may be used on any block item, including child blocks and prime
items.

Child blocks are schema references:

```txt
{ uint handler, uint resources, bytes32 key, #bytes as witness }
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
{ uint target, uint resources, #bytes as calldata.payload }
maybe #account as recipient.account
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
maybe #account as recipient at 1
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

STEP blocks use a plain `uint value` field containing native value drawn from
the pipeline budget. This is distinct from `resources`: STEP does not contain
or require interpretation of a chain-specific packed resource word.

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
Amount
asset_meta
asset-meta
0account
asset.
.asset
```

Reserved words include `maybe`, `many`, `as`, `at`, all field type names, and the
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
uint input = schema(1, 64, 64, 64, "{ bytes32 asset, uint amount }", bytes32(0));
```

Use different numeric keys when a host needs more than one local block key. The
key can also be a selector or any other `bytes4` value that is unique in the
context where it is used. The numeric arguments after the key are the minimum,
maximum, and allocation hint payload sizes. The alias names the block; the
schema string describes only the payload body.

## Standard Blocks

The complete canonical name/body catalog lives in `contracts/codec/Schema.sol`;
the corresponding keys and packed specifications live in `Keys.sol` and
`Specs.sol`. These names are intrinsic standard metadata and need not be emitted
in `#schema.name`:

```txt
bytes              ""
string             ""
list               ""
evm                ""
node               uint node
account            bytes32 account
asset              bytes32 asset
status             uint code
amount             bytes32 asset, uint amount
balance            bytes32 asset, uint amount
debt               bytes32 liability, uint debt
accountAsset       bytes32 account, bytes32 asset
assetLiability     bytes32 asset, bytes32 liability
hostAsset          uint host, bytes32 asset
bootstrap          bytes32 asset, uint amount, uint budget
allocation         uint host, bytes32 asset, uint amount
allowance          uint host, bytes32 asset, uint amount
custody            uint host, bytes32 asset, uint amount
accountAmount      bytes32 account, bytes32 asset, uint amount
hostAmount         uint host, bytes32 asset, uint amount
hostAccountAsset   uint host, bytes32 account, bytes32 asset
limits             uint limits
quote              bytes32 asset, bytes32 liability, bytes32 counterparty, uint limits
position           bytes32 asset, uint amount, bytes32 liability, uint debt
transaction        bytes32 from, bytes32 to, bytes32 asset, uint amount
hostAccountAmount  uint host, bytes32 account, bytes32 asset, uint amount
step               uint cmd, uint value, #bytes as input
call               uint target, uint resources, #bytes as payload
relay              #bytes as input, #bytes as steps
dispatch           uint portal, uint resources, #bytes as payload
context            bytes32 account, #bytes as state, #bytes as input
recover            uint handler, uint resources, bytes32 key, #bytes as witness
annotation         uint entity, #bytes as data
action             uint action
counterparty      bytes32 account
groups             #string as description
label              bytes32 namespace, #string as name
schema             uint spec, #string as body, bytes32 name
```

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
