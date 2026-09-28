# Indexing

Rootzero hosts publish discovery metadata and state changes through events so
off-chain indexers can reconstruct a repository — the catalog of endpoints,
labels, and access state, plus account balances and asset flows — from logs
alone, without contract artifacts, traces, or `eth_call`.

This document is the companion to [`Schema.md`](Schema.md): Schema.md describes
how to decode block payloads; this document describes what the log stream
guarantees, the event conventions hosts are expected to follow, and a small set
of proposed improvements. Sections marked **Proposed** are not yet implemented.

## Self-Describing ABI

Every event mixin emits `EventAbi` once from its constructor with the full ABI
string of the event it declares:

```txt
event EventAbi(string abi)
```

An indexer that replays a host's deployment logs learns the complete event ABI
of that host without artifact files. Only `EventAbi` itself must be known a
priori.

## Repository Discovery

The library guarantees the discovery layer. Each endpoint mixin emits one
discovery event from its constructor, so a host's deployment transaction
contains its full endpoint catalog:

```txt
event Endpoint(uint indexed host, uint id, uint descriptor)
```

- `descriptor` packs `[state key:4][input key:4][output key:4][source key:4]`,
  `[source block size:4][output block size:4][source shift:1][lanes:1]`,
  `[reserved:5][flags:1]`.
  From the least significant bit, the offsets are: flags 0, reserved 8,
  lanes 48, source shift 56, output block size 64,
  source block size 96, source key 128, output key 160, input key 192,
  and state key 224.
  Flag bits 0 and 1 mean `funded` and `admin`; bit 7 means `handoff`, bit 6 is
  reserved for endpoint-defined behavior, and bits 2 through 5 remain reserved
  for future protocol flags.
  Source shift 64 selects state; 0 selects input or no source. A zero source key
  identifies no source. Declared state takes precedence over input even when empty.
  Lane bits 0 and 1 indicate declared state and input, respectively.
  Block sizes are allocation estimates including the eight-byte header.
  When source length divides its nonzero block size exactly, execution estimates
  block count by division; otherwise it counts the leading matching block run.
  Output capacity is source block count times output block size. With no declared
  source, capacity defaults to one output block. An empty declared source estimates
  zero blocks. Execution opening allocates eagerly; capacity scaling is deferred.
  These estimates do not validate consumption; decoding validates the stream and
  the output buffer can grow. Schema annotations retain the full spec metadata.
  Indexers must decode descriptors according to the emitting deployment's format.
  A top-level list uses a context-local input key whose published schema body
  consists of one `many #item`, optionally wrapped in braces; nested lists in a
  body with sibling items continue to use the generic `#list` key.
- Command, port, query, and guard endpoints all share `Endpoint`; admin commands
  are marked by the descriptor's admin flag.
- Block schema strings are published as `#schema` blocks in `Annotation` events.
  Hosts may publish additional schema claims later through the admin `annotate`
  command.

An endpoint may publish `#groups { #string as description }` on its endpoint ID:
`#state as (debit, credit), #output as (receipt, change)`. Only grouped lanes are
listed. These endpoint-local references resolve through descriptor schemas; empty
lanes take precedence and their hints are ignored. Alias order and count describe
blocks per loop iteration. Omitted lanes remain unspecified. This annotation does
not change the descriptor, block encoding, allocation, or execution. The latest
trusted description replaces the whole earlier description; empty clears it.
See `Schema.md` for the grammar and invalid-hint handling.

Commands may publish `#executionCost { uint base, uint batch }` on their command
ID. The key is `bytes4(keccak256("#executionCost"))` and its payload is exactly
64 bytes, with base followed by batch. Estimate command execution as
`base + batch * batchCount` in destination-local execution units. Each batch is
one logical group processed by the command, including its constituent blocks.
Pipeline and transport overhead and safety margins are separate. Estimates are
advisory, not guaranteed bounds. Missing annotations or unknown batch counts
mean unknown cost. The latest trusted annotation replaces both fields; zero
values are valid estimates, not a clearing sentinel.

Annotation helpers are `ActionAnnot`, `CounterpartyAnnot`, `ExecutionCost`,
`GroupsAnnot`, `LabelAnnot`, and `SchemaAnnot`.
Their functions are `annotateAction`, `annotateCounterparty`, `executionCost`,
`annotateGroups`, `label`, and `schema`, respectively.

`ActivityEvent` (exported by `Events.sol`) provides
`Activity(bytes32 indexed account, uint codes, uint id)` for hosts to identify
an account activity while recording its effects through other events. The trailing
`id` is a correlation identifier: zero means no identifier is assigned, and must
not be used to join unrelated activities. Hosts should assign nonzero IDs uniquely
within the emitting contract; indexers scope them by chain and emitter address.
Child events can reference this ID when their schema supports it. Existing balance
and flow events do not carry this reference. Hosts choose where to emit activities
and must document any ordering used to associate effects when no explicit reference
is available. Emitters must pass `id` explicitly, including when it is zero.

`codes` packs up to eight total `uint32` action, effect, or state identifiers, starting in
the least significant 32 bits. Entries must be contiguous and nonzero, followed
by zero padding in the unused high slots. A zero word represents an empty list.
The event mixin does not validate packing; emitters are responsible for this
convention. Order and duplicates are preserved; adjacency does not imply
action-to-effect pairing. This is an ID list, not a bitmask. All codes fields share this format.

Use `Actions`, `Effects`, and `States`, all exported by `Events.sol` and `Utils.sol`.
The top three bits of each `uint32` code reserve space for eight categories;
the remaining 29 bits allow 536,870,912 values per category.

| Category | Meaning | Inclusive range |
|---|---|---|
| 0 | Actions | `0x00000000`–`0x1fffffff` |
| 1 | Reserved | `0x20000000`–`0x3fffffff` |
| 2 | Reserved | `0x40000000`–`0x5fffffff` |
| 3 | Reserved | `0x60000000`–`0x7fffffff` |
| 4 | Effects | `0x80000000`–`0x9fffffff` |
| 5 | States | `0xa0000000`–`0xbfffffff` |
| 6 | Reserved | `0xc0000000`–`0xdfffffff` |
| 7 | Reserved | `0xe0000000`–`0xffffffff` |

`Actions.None = 0` is reserved for the empty list or padding, leaving category 0
with one fewer usable identifier. Existing action and effect IDs are unchanged.
Effects define `Spend = 0x80000000`,
`Receive = 0x80000001`, `Lock = 0x80000002`, and `Unlock = 0x80000003`;
other effect IDs are reserved. There is no `Effects.None`: use zero for no codes.
Effects describe asset outcomes for the
account; actions describe the operations responsible. Asset IDs and quantities
remain in detail events rather than the activity summary.

States define `Inactive = 0xa0000000` and `Active = 0xa0000001`. Both are
nonzero: omitted state information is distinct from explicitly inactive. States
describe resulting conditions; each consumer defines which states apply. Asset, Node, Guardian, and Route
require exactly one Active or Inactive code; other events define their own requirements.

`Codes`, exported by `Events.sol` and `Utils.sol`, provides packed uint
combinations in action-catalog order, with each active/inactive pair together:

| Purpose | Active combination | Inactive combination |
|---|---|---|
| Membership | AddThenActive | RemoveThenInactive |
| Availability | EnableThenActive | DisableThenInactive |
| Authorization | AuthorizeThenActive | RevokeThenInactive |
| Roles | AppointThenActive | DismissThenInactive |
| Asset support | AllowThenActive | DenyThenInactive |

Each combination places the action first and resulting state second. They are
compile-time combinations of standard IDs, not a separate category. Pass them
directly as codes; hosts can define other combinations locally. Create and
Update do not imply a particular state, so callers compose those explicitly.

Each constant already includes its category bits, so a single action, effect, or state
can be passed directly without shifting. Category capacity is independent of
packing capacity: an activity still holds at most eight codes in total.

```solidity
emit Activity(account, Actions.Deposit, 0);
emit Activity(account, Effects.Lock, 0);
uint codes = uint(Actions.Swap) | (uint(Effects.Spend) << 32)
    | (uint(Effects.Receive) << 64);
emit Activity(account, codes, 0);
```

Cast each ID to `uint` before shifting so shifts beyond the first slot retain
their bits. To decode a word, read `uint32(word)` then shift `word >>= 32`, up to
eight times; zero terminates the list and all remaining slots must also be zero.
For each nonzero code, decode its category with `code >> 29` and its local
identifier with `code & 0x1fffffff`. Category 0 identifies actions, category 4 identifies effects, and category 5
identifies states; the other categories are reserved for future catalogs.
Unknown categories and unassigned identifiers have no defined meaning; indexers
should preserve the full code without interpreting it as a known action, effect, or state.

Names arrive as annotations. Each standard mixin emits a canonical label block
at construction, and the admin `annotate` command publishes mutable annotations
later:

```txt
event Annotation(uint indexed entity, bytes data)
#label { bytes32 namespace, #string as name }
```

Annotations are claims by the emitting contract: any contract may annotate any
entity, so indexers decide which emitters they trust per entity and annotation
type. Constructor label annotations emitted by the host itself are trustworthy
for that host's own endpoints. Consumers process annotation events in log order
and blocks within `data` in stream order.

`Annotation` is a policy-neutral envelope. There is no universal rule that a
later block replaces an earlier block: every annotation type defines its own
logical identity and merge behavior. A type may replace an earlier value,
accumulate distinct values, preserve every value as history, or define an
explicit revocation convention. Indexers must apply those type-specific rules
after checking the emitter they trust for that type.

The standard types currently use these rules:

- An `#action` is identified by its entity. The latest trusted action replaces
  the previous value; `Actions.None` clears the primary action classification.
- A `#counterparty` is identified by its entity. The latest trusted account
  replaces the previous counterparty, and account zero identifies Rootzero.
  Host accounts do not by themselves specify a settlement or realization route.
  Indexers interpret and validate the entity type in context and should require
  a host-node value before accepting a nonzero claim.
- A `#label` is identified by `(entity, namespace)`. The latest trusted label
  for that identity replaces its previous value; labels in different namespaces
  coexist.
- A `#schema` is identified by `(entity, block key)`. Schemas for distinct keys
  coexist, while the latest trusted schema claim for the same key replaces the
  earlier claim.

Indexers must ship the protocol's standard schema catalog: every built-in key
has a canonical alias, specification, and body. Standard aliases are known even
when no schema annotation is emitted or its body omits the optional `name:`
prefix. For example, `bytes4(keccak256("#balance"))` is canonically named
`balance`. A nonstandard key without a prefix remains unnamed; qualified
bindings such as `relay.input` require an explicit `relay.input:` prefix.
The `#schema` payload contains only `uint spec, #string as body`. Extract and
validate the prefix before registering the schema; `as` aliases name items
within the body and do not register schema names.

For name-based schema resolution, schemas emitted by the active host about its
own host ID take precedence over schemas from active trusted contexts, followed
by standard schemas. The latest local claim with the requested name wins.
Qualified names such as `relay.input` bind a schema to the encoded block stream
inside the aliased `#bytes` field at that structural path. Every contained
top-level block carries the selected schema's key, and its payload must satisfy
that schema's bounds and body. Invalid local bindings are reported and do not
fall back to a lower-precedence schema.

New annotation types must document their logical identity, whether values
replace or accumulate, and how values are revoked when revocation is supported.

Host topology and access state are fully evented by the library:

```txt
event Introduction(uint indexed host, uint peer, bytes32 origin, uint blocknum)
event Node(uint indexed host, uint node, uint codes)
event Guardian(uint indexed host, bytes32 account, uint codes)
```

`Introduction` fires on the receiving host when a peer host introduces itself
during construction. `origin` records `tx.origin` as a chain-agnostic user
account for provenance and must not be treated as authorization. Every
node-trust change routes through `authorizeNode` or `revokeNode` and every
guardian change through `appointGuardian` or `dismissGuardian`, so `Node` and `Guardian` are exhaustive:
replaying them yields the exact current access sets.

For both events, `codes` includes exactly one `States.Active` or
`States.Inactive` describing the resulting membership. Host emits
`Codes.AuthorizeThenActive` and `Codes.RevokeThenInactive` for nodes, including
guardian-triggered revocations, and `Codes.AppointThenActive` and
`Codes.DismissThenInactive` for guardians. Repeated operations still emit.
Indexers derive membership from the explicit state code independently of action
recognition. The numeric status field is removed; use the ABI for each deployment.

All account, asset, and node IDs are 32-byte values with one top-byte rule:
`0x00` is null/unset, `0x01` is Rootzero-native, `0x02` is opaque
`[0x02][category][subtype][bytes29(hash)]`, and `0x03` is EVM structured.
Structured EVM IDs use `[uint32 type][uint32 chainid][192-bit payload]`, where
`type` packs
`[uint8 representation][uint8 category][uint8 subtype][uint8 flags]`; see
`utils/Layout.sol`. Category and subtype are also present in opaque IDs, so
indexers can classify them without resolving the hash. Opaque IDs still need
host-specific lookup or witness data when the underlying account, asset
metadata, or node target is needed.
Command subtype `0x03` identifies every command. Flag bit 7 identifies a
pipeline handoff command whose STEP input and remaining continuation are wrapped
automatically in a RELAY block.
Endpoint IDs and descriptors carry the same flags, so indexers can verify their
metadata directly.
Opaque preimages use `[formatHash][category][subtype][payload...]`; `0x01`
means keccak256. The category and subtype must match the ID. The remaining
bytes are host/domain-specific for now.

`Derived` and `Virtual` remain reserved asset subtypes. No standardized
subtype-specific preimage payload or dedicated helper is currently provided.

### Cold-Start Recipe

1. Start from the chain's configured commander host ID, resolve its native
   target, and replay its deployment logs: `EventAbi` gives the event ABIs,
   the discovery events give the endpoint catalog, and `Annotation` label blocks
   give names.
2. Follow `Introduction` events on the commander to enumerate hosts. The `peer`
   ID embeds the introduced host's address; the receiving `host` is the
   commander that accepted the introduction, and the peer's admin account
   derives from the native identity encoded by the commander host ID.
3. For each host, repeat step 1 against its deployment logs, then replay
   `Node` and `Guardian` for live access sets.
4. Subscribe to the state events below for balances and flows.

The endpoint repository — commands, admin commands, ports, queries, and guards
with schemas, names, and access state — is fully reconstructible from logs
today. No changes are proposed to the discovery layer.

## State Events

Most state-event emission remains a host responsibility: asset and ledger
mutation flows through virtual hooks (`deposit`, `withdraw`, `burn`,
`creditAccount`, `debitAccount`, `payout`, the realization commands, `provision`, `allowAsset`,
`denyAsset`, ...), and the hook implementation is the layer that knows the
host's ledger policy - in particular the asset binding and the resulting
balance. Command-returned native credit replenishes the pipeline budget. The
enclosing entrypoint settles the final budget through its host hooks, so the
ledger emits one receiving event. `portPipePayable` calls `cashin` for the last
context's account only when both that account and the remaining budget are nonzero.
Empty input or a zero final account skips `cashin` and returns the remaining budget
as credit; this path emits no receiving event through `cashin`.
The `create-rootzero` template
(`rootzero-evm-commander`) is the reference implementation of the remaining
host conventions.

```txt
event Balance(bytes32 indexed account, bytes32 asset, uint balance)
event Positioned(bytes32 indexed account, bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty, uint codes)
event Settled(bytes32 indexed account, bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty)
event Received(bytes32 indexed account, bytes32 asset, uint amount, uint codes)
event Spent(bytes32 indexed account, bytes32 asset, uint amount, uint codes)
event Locked(bytes32 indexed account, bytes32 asset, uint amount, uint codes)
event Unlocked(bytes32 indexed account, bytes32 asset, uint amount, uint codes)
event Asset(uint indexed host, bytes32 asset, uint codes)
event AssetPreimage(bytes32 indexed asset, bytes preimage)
event Route(uint indexed host, uint portal, uint codes)
event Rooted(bytes32 indexed account, uint deadline, uint value)
```

### Host Conventions

`AssetPreimage` publishes an opaque asset's preimage, with the asset ID as the
indexed field and no host argument. The emitting contract remains available in
the log address; consumers validate that the preimage derives the declared ID.
This event declares a preimage and does not imply support on a host.

`Asset` records an asset lifecycle or administrative action and its resulting
active/inactive state on a host. `Actions.Create` means creation and
`Actions.Delete` means deletion. Support decisions use `Codes.AllowThenActive`
and `Codes.DenyThenInactive`. Hosts supply emissions and must include exactly
one `States.Active` or `States.Inactive`, consistent with the resulting state.
Create and Update can result in either state; callers select it explicitly.
Indexers retain action codes to distinguish operations and derive membership
from the state code even when an action is unrecognized. The event no longer
carries arbitrary numeric status. The `assetCodes` query returns one `#codes`
block per requested `#asset`, preserving order. Its hook returns exactly one
Active or Inactive code describing the current condition, rather than historical
actions/effects. Zero does not mean inactive. This replaces `assetStatus` and
its `#status` response; empty input still returns empty output.

Preimage emitters inherit `AssetPreimageEvent`; asset action emitters use
`AssetEvent`. Both are exported by `Events.sol`. Historical Asset and
AssetStatus event signatures must be decoded with their deployment's ABI.

`Route` records the operation on a host's route to a portal and its resulting
active/inactive state. Use `Codes.AddThenActive` and `Codes.RemoveThenInactive`
for route membership changes, and `Codes.EnableThenActive` and
`Codes.DisableThenInactive` for a route that remains configured. These describe
the route, not creation or deletion of the destination portal. Hosts supply
consistent emissions, including repeated operations. Exactly one Active or
Inactive code is required; no numeric status field remains.

A host that wants to be indexable from logs alone must follow these rules. A
host that omits them still works on-chain, but its ledger is invisible to
log-based tooling - there is no fallback channel, because command output
(`state` and native `credit`) is return data and inputs are calldata.

**Root identity.** The trusted commander host ID is off-chain configuration.
Indexers resolve its runtime-native target and derive the native asset ID from
its chain context. A root host labels itself with an
`Annotation` containing a `#label` block. Child hosts are discovered through
`Introduction` on their commander.

**Balances.** The `Balance` event identifies a `bytes32` account, asset,
and resulting total. The built-in `Balances` ledger keys every
balance by `(account, asset)`, including host holdings under `Accounts.toHost(host)`.
Its mutation helpers leave event emission to the host. There is no separate
host balance event or ledger.

Each event replaces the indexed balance for `(emitting host, account, asset)`.
Process events in block, transaction, and log order. Hosts that expose their
ledger through logs must emit a resulting balance for every change at their
chosen settlement boundary. Indexers may derive `change = balance - previousBalance`
using arbitrary-precision signed arithmetic; an unknown previous balance is not
implicitly zero. A stream indexed from initialization, or a consistent starting
snapshot, is required to reconstruct deltas. The event itself supports the full
uint256 balance range.

The three-field signature changes topic zero from the former four-field event.
Indexers spanning both versions must decode each signature separately, using
the published `EventAbi` metadata.

**Positions.** An action that exposes a resulting live position may emit
`Positioned` with both the asset and liability sides, the counterparty, and the primary `Actions`
code that produced them. The event records the emitting host's observation of
the transient pipeline position; it does not by itself prove that either side
was persisted or settled.

After fully settling a position, a host may emit `Settled` with the account,
counterparty, and settled asset and debt quantities. Only `account` is indexed.
Emit it once per position after the settlement hook succeeds. These are the
final quantities supplied by the producer; settlement adds no host fee.
Producers record any separate fee payments in their own flow events.
Hosts opt into emission through `SettledEvent`.

**Flows.** Operations that move value emit one flow event per affected amount,
with the matching `Actions` code:

| Operation                  | Event      | `codes`            |
| -------------------------- | ---------- | ------------------ |
| deposit / depositPayable   | `Received` | `Actions.Deposit`  |
| withdraw                   | `Spent`    | `Actions.Withdraw` |
| cashout (host implementation) | `Spent` | `Actions.Cashout` |
| burn                       | `Spent`    | `Actions.Burn`     |
| creditAccount              | `Received` | `Actions.Transfer` |
| debitAccount               | `Spent`    | `Actions.Transfer` |
| payout                     | `Spent` / `Received` | `Actions.Payout` |
| realize                    | host-defined | `Actions.Realize` |
| final pipeline budget      | `Received` | host posting action |
| provision (lock custody)   | `Locked`   | per operation      |
| custody release            | `Unlocked` | per operation      |

`CashoutHook` is abstract and has no event-emitter inheritance. Hosts implementing
cashout are responsible for their own flow events and event ABI publication.
The free `sendChainAsset` transfer helper emits no events; hosts may emit
`Spent(account, chainAsset, amount, Actions.Cashout)` after a successful
payout according to their event policy.

`Balance` and flow events are complementary, not redundant: flow events record
that value moved and why; balance events record the resulting total, which gives
indexers a checkpoint that survives missed deltas. An operation that both moves
value and changes a ledger total emits both.

Command native credit is trusted return data and produces no immediate ledger
event. It can fund later steps; the enclosing entrypoint emits through the host
settlement hooks (including `cashin` for the pipeline port) only when it settles
the final budget. Synchronous EVM execution
remains atomic: if settlement or a later pipeline step reverts, its event is
reverted as well.

**Asset gating.** Hosts that gate assets emit `Asset` from their
`allowAsset`/`denyAsset` hooks, with `Codes.AllowThenActive` or
`Codes.DenyThenInactive` describing the resulting support state.

**Opaque assets.** Hosts that create or register opaque asset IDs emit `AssetPreimage`
with the canonical preimage used to resolve the asset. Indexers should treat
`asset` as the ledger key and can verify host-specific opaque IDs by checking
`asset == 0x02 || preimage[1:3] || bytes29(hash(preimage))`. The preimage starts
with `[formatHash][category][subtype]`; `0x01` means keccak256, and the category
must be `Asset`. The rest of the payload is not yet standardized.

**Invocations.** Top-level pipeline entrypoints emit `Rooted` once per
invocation with the acting account, deadline, and attached value. Detailed
effects are not duplicated into the invocation event; an indexer groups all
logs of the transaction to attribute effects to the invocation.

### Codes and Correlation

All events carrying codes use the same uint packing as Activity: up to eight
nonzero uint32 action/effect/state IDs, lowest slot first, with zero-filled unused high
slots. Zero means no codes. Order and duplicates are preserved; adjacency does
not pair actions with effects. Each ID includes its category bits: category 0
is Actions, category 4 is Effects, category 5 is States, and other categories remain reserved.
A single Actions, Effects, or States constant can be passed directly. When composing
multiple codes in Solidity, widen to uint before shifting by 32 bits or more.

Asset, Node, Guardian, and Route require exactly one occurrence of either
States.Active or States.Inactive. Missing, duplicate, or conflicting membership
state codes violate their convention; indexers must not infer a valid membership
update from such logs. Event declarations perform no runtime validation, so
emitters are responsible for satisfying the convention. Other code categories
may coexist and retain their ordinary ordering and duplicate rules.

Codes describe this event's operations or outcomes. Typed event fields remain
authoritative; Received already denotes receipt, so Effects.Receive is optional.
The unused context fields have been removed from Received, Spent, Locked, and
Unlocked. These events make no endpoint-correlation claim. Activity.id retains
its separate correlation convention.

Replacing uint32 action with uint codes changes event signature topics. Removing
context also changes flow-event arity. Decode historical logs using the ABI for
their emitting deployment; do not apply the new signatures retrospectively.

**Shared action semantics.** In every event carrying `codes`, each action ID states
which operation occurred. Its canonical meaning is the same across event types:
`Actions.Create` means creation, `Actions.Delete` means deletion,
`Actions.Add`/`Actions.Remove` mean membership changes, and
`Actions.Refund` means a refund. The event identifies the affected entity or
effect and supplies context. Resulting state codes do not redefine the action. For example,
`Asset(host, asset, uint(Actions.Create) | (uint(States.Inactive) << 32))`
records an asset that was created but is inactive on that host, not a denial.
Consumers should retain the action even when different operations produce the
same state. Hosts choose applicable actions and must emit them truthfully.

| Range | Group | Assigned codes | Reserved |
| --- | --- | --- | --- |
| 0-15 | Lifecycle and membership | None 0, Create 1, Update 2, Delete 3, Add 4, Remove 5, Enable 6, Disable 7 | 8-15 |
| 16-31 | Permissions and roles | Authorize 16, Revoke 17, Appoint 18, Dismiss 19, Allow 20, Deny 21 | 22-31 |
| 32-47 | Transfers | Transfer 32, Payout 33, Deposit 34, Withdraw 35, Cashin 36, Cashout 37 | 38-47 |
| 48-63 | Supply | Mint 48, Burn 49 | 50-63 |
| 64-79 | Accounting and settlement | Post 64, Book 65, Realize 66, Settle 67, Fee 68, Refund 69 | 70-79 |
| 80-95 | Trading and credit | Swap 80, Borrow 81, Repay 82, Liquidate 83 | 84-95 |

Values 96 and above are reserved for future groups. Unassigned values must not
be used as custom actions. Ranges organize the catalog and imply no permissions
or runtime dispatch. An event's contract defines which actions apply and what
its typed fields describe, while preserving canonical action meanings.

**Numeric compatibility:** the grouped catalog replaces the assignments used
through v1.41.0. Event signatures and `#action` block keys do not identify the
catalog version. Indexers must select the mapping for the emitting deployment
(and implementation epoch for upgraded hosts), never reinterpret older logs or
annotations with the new mapping. The previous catalog was:

```txt
None 0, Transfer 1, Payout 2, Settle 3, Deposit 4, Withdraw 5, Fee 6,
Mint 7, Burn 8, Swap 9, Borrow 10, Repay 11, Liquidate 12, Refund 13, Post 14,
Cashout 15, Cashin 16, Realize 17, Book 18
```

Joins available to an indexer: transaction grouping -> the `Rooted` invocation and sibling
events; `(account, asset)` -> account balance and flow history, including host
accounts. Balance events have no endpoint correlation field.

## Proposed Improvements

The discovery layer needs nothing. The proposals below close the remaining
gaps; none of them changes an existing event signature or topic, so all are
non-breaking per the changelog conventions.

### Proposed: Emitting Ledger Helpers

Add opt-in helpers to `Balances` that combine ledger mutation with emission
of `Balance(account, asset, balance)`. Keep the existing raw helpers for
hosts that emit at their settlement boundary.

## Considered And Rejected

These were evaluated and deliberately not proposed:

- **Per-invocation input/response events.** Input payloads are already in
  calldata and outputs in return data; logging them would roughly double the
  byte cost of every call. `Rooted` already marks invocations, and reverted
  calls emit no logs anyway, so such events cannot provide failure
  observability. The protocol's position stands: emit focused semantic events
  instead of mirroring complete input and output block streams into logs.
- **Unconditional library-forced flow emission for hook-driven commands.** Hosts
  route hooks internally (e.g. a payout hook that calls the credit hook), so
  unconditional emission at that layer would double-count or misattribute.
  Command credit remains in the pipeline budget for the same reason, avoiding
  producer-side events and repeated intermediate settlement.
- **Inventing an emitter for `Rooted` in the library.** `Rooted` belongs to host
  entrypoints the library does not own.
- **A dedicated event and command for every metadata type.** Entity metadata is
  carried by typed blocks inside `Annotation`, with the generic admin `annotate`
  command publishing later updates.

## Compatibility

Replacing `Labeled` and `Schema` with block-based `Annotation` changes the
discovery event surface and is breaking for indexers that consume the former
events. Consumers must decode annotation block streams and recognize `#label`
blocks for names and `#schema` blocks for block definitions.

The unified `Balance` event identifies an indexed account (`bytes32`) without
`access`. Host holdings use the deterministic host account. Indexers must replace
the former `AccountBalance` and host-indexed `Balance` subscriptions with this
single event signature.
