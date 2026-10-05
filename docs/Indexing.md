# Indexing

Rootzero hosts publish discovery metadata and state changes through events so
off-chain indexers can reconstruct a repository — the catalog of endpoints,
labels, and access state, plus account balances and asset flows — from logs
alone, without contract artifacts, traces, or `eth_call`.

This document is the companion to [`Schema.md`](Schema.md): Schema.md describes
how to decode block payloads; this document describes what the log stream
guarantees and the event conventions hosts are expected to follow.

## Block-based discovery

Protocol discovery and state logs use LOG0 with canonical block schemas.
Indexers preload the standard key/schema and code catalogs, then learn endpoint
lanes and custom schemas from deployment logs. The library no longer provides
ABI-event mixins, EventEmitter, EventAbi, or the Events.sol barrel.
Code catalogs are exported through Utils.sol and logging through Codec.sol.
Applications may still declare ordinary Solidity events and supply their ABIs
through their own tooling; historical EventAbi-based deployments retain their
original decoding conventions.

## Repository Discovery

The library guarantees the discovery layer. Each endpoint mixin emits one
discovery event from its constructor, so a host's deployment transaction
contains its full endpoint catalog:

```txt
[Codes.HostAdd:32][#endpoint { uint id, uint state, uint input, uint output }]
```

- `state`, `input`, and `output` are packed lanes: `[spec:16][codes:16]`.
  Mask off the lower 128 bits to recover the spec, whose fields remain
  `[key:4][min:4][max:4][hint:3][reserved:17]`. The lower 128 bits hold four
  uint32 code slots. Nonzero codes select logging; a zero spec declares no schema.
  A maximum of zero is unbounded; bounds and hints describe payload bytes.
- Command, port, query, and guard endpoints all share `Endpoint`. Endpoint
  behavior flags come from `id`: `(id >> 224) & 0xff`. Bits 0 and 1 mean
  `funded` and `admin`; bit 7 means `handoff`. Bits 2-5 are unassigned and bit 6
  is reserved for endpoint-defined behavior. Lane codes select logging separately.
- Registration still derives an execution descriptor for runtime opening and
  allocation. That descriptor is internal metadata and is no longer emitted.
  Indexers resolve schemas from the three published specs. A top-level list can
  use a context-local key with a schema body containing one `many #item`;
  nested lists with siblings continue to use `#list`.
- Registration uses LOG0, without topics or an EventAbi announcement. Codes.HostAdd
  packs Entities.Host then Actions.Add. The emitter and chain identify the
  publishing host through the standard host-ID convention; no host word is repeated.
  Indexers preload these codes and the canonical Endpoint key
  (bytes4(keccak256("#endpoint"))) and four-word layout before decoding discovery.
  This avoids depending on an endpoint registration to decode its own announcement.
- Decode historical Endpoint ABI logs using their published EventAbi and deployment
  version; their descriptor/spec-only/lane layouts retain their original semantics.
- Block schema strings are published as `#schema` blocks inside LOG0 `#annotation` envelopes.
  Hosts may publish additional schema claims later through the admin `annotate`
  command.

An endpoint may publish `#groups { #string as description }` on its endpoint ID:
`#state as (debit, credit), #output as (receipt, change)`. Only grouped lanes are
listed. These endpoint-local references resolve through published endpoint specs; empty
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

Account activity uses scoped codes and typed blocks in command state/input/output
logs or standalone LOG0 streams. Balance blocks carry asset amounts; Position and
account-bearing blocks provide richer detail. Effects.Spend, Receive, Lock and
Unlock describe movement alongside the operation's action codes.
Account scope must resolve to an explicit account-bearing block or documented
pipeline context; a scope-kind code alone does not identify an account.
ActivityEvent and RouteEvent and their public exports have been removed. Replay
historical ABI logs with their original EventAbi and deployment conventions.

`codes` packs up to eight total `uint32` action, entity-kind, effect, or state identifiers, starting in
the least significant 32 bits. Entries must be contiguous and nonzero, followed
by zero padding in the unused high slots. A zero word represents an empty list.
The logging primitives do not validate packing; emitters are responsible for this
convention. Order and duplicates are preserved; adjacency does not imply
action-to-effect pairing. This is an ID list, not a bitmask. All codes fields share this format.

Use `Actions`, `Entities`, `Effects`, and `States`, all exported by `Utils.sol`.
The top three bits of each `uint32` code reserve space for eight categories;
the remaining 29 bits allow 536,870,912 values per category.

| Category | Meaning | Inclusive range |
|---|---|---|
| 0 | Actions | `0x00000000`–`0x1fffffff` |
| 1 | Entities | `0x20000000`–`0x3fffffff` |
| 2 | Reserved | `0x40000000`–`0x5fffffff` |
| 3 | Reserved | `0x60000000`–`0x7fffffff` |
| 4 | Effects | `0x80000000`–`0x9fffffff` |
| 5 | States | `0xa0000000`–`0xbfffffff` |
| 6 | Reserved | `0xc0000000`–`0xdfffffff` |
| 7 | Reserved | `0xe0000000`–`0xffffffff` |

`Entities` classifies the associated subject; it does not replace its full-width
identity. Kind codes are optional when the event or subject ID already supplies
that information. The catalog assigns `Asset = 0x20000000`, `Account = 0x20000001`,
`Host = 0x20000002`, `Command = 0x20000003`, `Query = 0x20000004`,
`Route = 0x20000005`, `Position = 0x20000006`, `Guardian = 0x20000007`, and
`Pool = 0x20000008`, `Port = 0x20000009`, and `Balance = 0x2000000a`.
Other category-1 values are reserved. There is no
`Entities.None`; zero remains the empty list or padding.

`Actions.None = 0` is reserved for the empty list or padding, leaving category 0
with one fewer usable identifier. Existing action and effect IDs are unchanged.
Effects define `Spend = 0x80000000`,
`Receive = 0x80000001`, `Lock = 0x80000002`, and `Unlock = 0x80000003`;
other effect IDs are reserved. There is no `Effects.None`: use zero for no codes.
Effects describe asset outcomes for the
account; actions describe the operations responsible. Asset IDs and quantities
are carried by the typed blocks in the logged stream.

States define `Inactive = 0xa0000000` and `Active = 0xa0000001`. Both are
nonzero: omitted state information is distinct from explicitly inactive. States
describe resulting conditions; each consumer defines which states apply. Asset and route membership logs (and historical Node/Guardian events)
require exactly one Active or Inactive code; other events define their own requirements.

`Codes`, exported by `Utils.sol`, provides packed uint
combinations in action-catalog order, with each active/inactive pair together:

| Purpose | Active combination | Inactive combination |
|---|---|---|
| Membership | AddThenActive | RemoveThenInactive |
| Availability | EnableThenActive | DisableThenInactive |
| Authorization | AuthorizeThenActive | RevokeThenInactive |
| Roles | AppointThenActive | DismissThenInactive |
| Asset support | AllowThenActive | DenyThenInactive |

The two-slot combinations above place the action first and resulting state second. They are
compile-time combinations of standard IDs, not a separate category. Pass them
directly as codes; hosts can define other combinations locally. Create and
Update do not imply a particular state, so callers compose those explicitly.
Scoped log combinations put the scope entity kind in the first (lowest uint32)
slot. Remaining slots describe the subject, operation and result in the order
specified by the named combination; no universal order applies to those slots.
Legacy unscoped combinations and event families retain their existing semantics.
Do not reinterpret their first action as a scope.

Scope kinds are not identities. Each event family must define where its actual
scope ID and affected subject IDs come from. Host-scoped endpoint logs resolve
host identity through the trusted Endpoint registration, keyed by chain, emitter
and endpoint ID. Index each affected subject as well as that host. Account-scoped
logs require an explicit account block or a reliably associated execution/root
context; an Account code alone cannot recover the account. Unknown scope kinds
or unresolved IDs must not be guessed from adjacent logs.

Account operations use `Codes.AccountWithdraw`, `Codes.AccountDeposit`,
`Codes.AccountCredit`, and `Codes.AccountDebit`. Each packs `Entities.Account`
first and the corresponding action second. Commands combine these codes with a
spec, for example `Specs.Balance | Codes.AccountWithdraw`. These names preserve
the existing encoded values and do not add a redundant Balance entity code.

`Codes.AddRouteThenActive` explicitly combines `Actions.Add`,
`Entities.Route`, and `States.Active` in that order:

```solidity
uint codes = Actions.Add | (Entities.Route << 32)
    | (States.Active << 64);
```

The entity kind occupies one of the eight available slots. This named combination
describes an active added route; arbitrary code adjacency still does not
establish causal pairing.

`Codes.RemoveRouteThenInactive` is the corresponding removal combination:
`Actions.Remove`, `Entities.Route`, and `States.Inactive`, in that order.

`Codes.AllowAssetThenActive` combines `Actions.Allow`, `Entities.Asset`, and
`States.Active`. Its counterpart, `Codes.DenyAssetThenInactive`, combines
`Actions.Deny`, `Entities.Asset`, and `States.Inactive`. Both use three slots;
the existing `AllowThenActive` and `DenyThenInactive` omit the entity kind.

Each constant already includes its category bits, so a single action, entity-kind, effect, or state
can be passed directly without shifting. Category capacity is independent of
packing capacity: an activity still holds at most eight codes in total.

```solidity
uint codes = Entities.Account | (Actions.Deposit << 32) | (Effects.Receive << 64);
// The surrounding documented context must identify the affected account.
bytes memory data = Encoder.createBalance(asset, amount);
Logs.mem(codes, Encoder.pos(data, 0), data.length);
```

Catalog constants already use `uint`, so shifts retain their bits. To decode a word, read `uint32(word)` then shift `word >>= 32`, up to
eight times; zero terminates the list and all remaining slots must also be zero.
For each nonzero code, decode its category with `code >> 29` and its local
identifier with `code & 0x1fffffff`. Category 0 identifies actions, category 1 identifies entity kinds, category 4 identifies effects, and category 5
identifies states; the other categories are reserved for future catalogs.
Unknown categories and unassigned identifiers have no defined meaning; indexers
should preserve the full code without interpreting it as a known action, entity-kind, effect, or state.

Names arrive as annotations. Each standard mixin emits a canonical label block
at construction, and the admin `annotate` command publishes mutable annotations
later:

```txt
[codes:32][#annotation { uint entity, #bytes as data }]
#label { bytes32 namespace, #string as name }
```

Standalone annotation logs use `Codes.HostAnnotate` (`Entities.Host` followed by
`Actions.Annotate`, action 8). The scope is the publishing host, resolved from the
chain and emitting contract's address using the standard host-ID convention;
verified endpoint registrations also identify that host. `entity` is the annotated
subject and remains a full-width uint, with no restriction to a particular ID kind.
Index claims by publisher, annotated entity and annotation-type identity.

`Logs.annotation(entity, data, codes)` constructs an ANNOTATION block using
`Encoder.createAnnotation` and emits it through `Logs.mem`. Standard annotation
helpers supply HostAnnotate codes. The `annotate` admin command instead logs one
`[endpoint ID:32][INPUT header][ANNOTATION blocks...]` batch from existing calldata.
The one-shot admin runner authorizes before logging; takeAnnotations validates
every envelope and its BYTES child without interpreting the enclosed claims.
Resolve its scope/codes through Endpoint metadata, then process each annotation
in stream order. Empty input emits an empty INPUT container; a failed batch leaves
no logs. Both paths preserve the same annotation payloads and merge semantics.

Indexers preload the canonical Annotation, Bytes, Input and Schema layouts to
bootstrap discovery. The removed `AnnotationEvent` mixin no longer emits an ABI
announcement; historical Annotation ABI logs retain their original decoder.

Annotations are claims by the emitting contract: any contract may annotate any
entity, so indexers decide which emitters they trust per entity and annotation
type. Constructor label annotations emitted by the host itself are trustworthy
for that host's own endpoints. Consumers process annotation events in log order
and blocks within `data` in stream order.

`#annotation` is a policy-neutral envelope. There is no universal rule that a
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

Recovery records use one fixed-size Resolution block:

```txt
[Codes.HostUnresolved:32][#resolution { bytes32 key, bytes32 digest }]
[Codes.HostResolved:32][#resolution { bytes32 key, bytes32 digest }]
```

The combinations pack Entities.Host then States.Unresolved (0xa0000010) or
States.Resolved (0xa0000011). Index records by chain, emitter, key and digest;
the emitter identifies the owning host. Unresolved records a retained digest.
Resolved means the matching record was consumed, not independent downstream
delivery success. Portal logs consumption inside resolve; a later recovery revert
rolls back the storage deletion and log together. Reusing a key can replace its
digest, so preserve the digest in both records and apply logs in order.
Logs.resolution only encodes and logs; Portal retains storage and witness checks.
The old ResolvedEvent/UnresolvedEvent mixins and exports are removed. Preload the
Resolution schema; historical ABI events retain their original decoder.

Host topology uses one LOG0 record on the receiving host:

```txt
[Codes.HostIntroduce:32][#introduction { uint peer, bytes32 origin, uint blocknum }]
```

Codes.HostIntroduce packs Entities.Host followed by Actions.Introduce (9).
The emitter identifies the receiving host; peer is the introducing host and must
match msg.sender. This records a discovery claim without granting authorization
or trust. origin records tx.origin as a user account for provenance.
blocknum is a caller-supplied claim, not a verified deployment block. Built-in
outbound helpers supply the current block number, including when called after
deployment. Indexers can use the receipt block for the observed introduction time.
Preload the canonical Introduction key and three-word layout alongside Endpoint
discovery. No Introduction ABI announcement is emitted; historical ABI logs retain
their original decoder.

Host authorization and guardian changes now use endpoint-prefixed LOG0 INPUT
batches instead of per-item Node and Guardian events:

| Endpoint | Scope | Subject blocks | Codes after scope |
|---|---|---|---|
| authorize / ExecuteAuthorize | Host | Node | Authorize, Active |
| unauthorize / guardian revoke | Host | Node | Revoke, Inactive |
| appoint | Host | Account | Guardian, Appoint, Active |
| dismiss | Host | Account | Guardian, Dismiss, Inactive |

The endpoint registration supplies lane codes; its emitter identifies the host. Each Node or
Account block supplies an affected subject ID. Index authorization by host and
node, and guardian membership by host and guardian account. Active/Inactive sets
the resulting boolean; repeated operations remain idempotent. Empty batches
emit an empty INPUT container and change no membership. Logs precede the hooks
after access checks and roll back with any failed operation.

The default Host validates IDs without transforming them, so these input batches
reconstruct its access sets when mutations use the advertised entrypoints.
Internal mutation hooks no longer emit events: custom entrypoints, constructor
initialization and overrides must provide equivalent logging and honor advertised
semantics if their state is to be reconstructed. ExecuteAuthorize explicitly
logs the same input envelope as the admin runner; guardian revoke logs through
its guard runner.

NodeEvent and GuardianEvent mixins and their public exports have been removed.
Custom emitters must migrate to scoped input logs or explicitly declared custom
logs. Historical deployments still have topic-based Node/Guardian logs: decode
those using their advertised ABI. Other event families remain unchanged during
this migration.

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
Indexers read behavior flags directly from endpoint IDs. Runtime descriptors
derive internal logging selections from lane codes and are not published.
Opaque preimages use `[formatHash][category][subtype][payload...]`; `0x01`
means keccak256. The category and subtype must match the ID. The remaining
bytes are host/domain-specific for now.

`Derived` and `Virtual` remain reserved asset subtypes. No standardized
subtype-specific preimage payload or dedicated helper is currently provided.

### Cold-Start Recipe

1. Start from the chain's configured commander host ID, resolve its native
   target, and replay its deployment logs using the canonical block catalog:
   the discovery events give the endpoint catalog, and `Annotation` label blocks
   give names.
2. Follow `Introduction` blocks on the commander to enumerate hosts. The `peer`
   ID embeds the introduced host's address; the receiving `host` is the
   commander that accepted the introduction, and the peer's admin account
   derives from the native identity encoded by the commander host ID.
3. For each host, repeat step 1 against its deployment logs, then replay
   host-scoped authorization/guardian INPUT logs for live access sets (legacy
   deployments use Node and Guardian events).
4. Subscribe to the state events below for balances and flows.

The endpoint repository — commands, admin commands, ports, queries, and guards
with schemas, names, and access state — is fully reconstructible from logs
today. No changes are proposed to the discovery layer.

## State Events

Most state-event emission remains a host responsibility: asset and ledger
mutation flows through virtual hooks (`deposit`, `withdraw`, `burn`,
`creditAccount`, `debitAccount`, `payout`, the realization commands, `allowAsset`,
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

### Host Conventions

Asset metadata and lifecycle records use LOG0 block streams:

```txt
[Codes.AssetAnnotate:32][#assetPreimage { bytes32 asset, #bytes as preimage }]
[host-scoped action/state codes:32][#asset { bytes32 asset }]
```

Codes.AssetAnnotate packs Entities.Asset then Actions.Annotate. Index by the asset
field and retain the emitter as the publisher of the claim. Validate that the
complete preimage derives the declared opaque ID before accepting the claim.
This declares metadata; it implies neither asset creation nor support on a host.
The encoder preserves bytes without validating that correspondence.

Lifecycle logs start with Entities.Host, followed by action and resulting-state
codes. The emitter identifies the host; use a #hostAsset block containing an
explicit host ID when reporting about another host. Actions.Create means creation
and Actions.Delete means deletion. Support decisions use Allow then Active or
Deny then Inactive after the host-scope slot. Hosts supply emissions and include
exactly one States.Active or States.Inactive consistent with the resulting state.
Create and Update can result in either state; callers select it explicitly.
Indexers retain action codes to distinguish operations and derive membership
from the state code even when an action is unrecognized. The event no longer
carries arbitrary numeric status. The `assetCodes` query returns one `#codes`
block per requested `#asset`, preserving order. Its hook returns exactly one
Active or Inactive code describing the current condition, rather than historical
actions/effects. Zero does not mean inactive. This replaces `assetStatus` and
its `#status` response; empty input still returns empty output.

For generic entities, `entityCodes` accepts `#entity { uint entity }` blocks and
returns one `#codes` per input, preserving order and duplicates. The hook defines
entity kinds and applicable current conditions; Active/Inactive is optional where it does not
apply. Zero codes means unknown or no condition reported, not inactive. This
query does not report historical actions or effects and does not reconstruct
event history. The query preserves the hook's codes without semantic validation.

Prefer endpoint state/input/output lane logging for existing asset streams.
For standalone preimage publication, construct a block with Encoder.createAssetPreimage
and emit it through Logs.mem with Codes.AssetAnnotate. Existing calldata streams
can use Logs.copy. These primitives do not validate codes or claims.
AssetEvent and AssetPreimageEvent and their public exports are removed; no ABI
announcement is emitted. Preload the Asset and AssetPreimage schemas to decode
these logs. Historical Asset, AssetPreimage and AssetStatus ABI events retain
their deployment-specific decoders.

Route changes use command state/input/output logs identifying the portal, or
equivalent standalone block streams. Pack Entities.Host first and include
Entities.Route where the block shape alone does not identify the route relationship.
Use Add/Remove for membership and Enable/Disable for a configured route, with
exactly one resulting Active/Inactive state. These describe the route, not creation
or deletion of the destination portal. Index by host and portal, including repeated
operations. No replacement Route event envelope or dedicated log helper is needed.

A host that wants to be indexable from logs alone must follow these rules. A
host that omits them still works on-chain, but its ledger is invisible to
log-based tooling - there is no fallback channel, because command output
(`state` and native `credit`) is return data and inputs are calldata.

**Root identity.** The trusted commander host ID is off-chain configuration.
Indexers resolve its runtime-native target and derive the native asset ID from
its chain context. A root host labels itself with an
`Annotation` containing a `#label` block. Child hosts are discovered through
`Introduction` on their commander.

**Balances.** Use Balance blocks with documented account context, or AccountAmount
blocks carrying the account explicitly. The built-in Balances ledger keys every
balance by (account, asset), including host holdings under Accounts.toHost(host).
Its mutation helpers emit no logs; commands or custom callers provide logging.

The endpoint's codes and documented semantics distinguish deltas from resulting
totals. Credit/debit flows can reconstruct balances by ordered deltas; a resulting
total supplies a checkpoint. Do not treat every Balance block as a resulting total.
An unknown starting balance is not implicitly zero. All amounts retain uint256 width.

The old BalanceEvent and its ABI announcement are removed. Decode historical
three-field and four-field Balance ABI events using their original definitions.

**Transport.** Relay and Dispatch use Envelope blocks with scope/action codes.
The old RelayEvent and DispatchEvent mixins are removed. Host scope resolves from
the emitter; account scope needs documented pipeline context or explicit blocks.
Envelope.digest hashes the exact forwarded payload bytes. Legacy ABI logs permitted
payload-or-envelope digests; retain deployment-specific rules for those records.

**Positions.** The `swapExactIn` and `swapExactOut` commands emit one
[endpoint-prefixed OUTPUT log](#command-runner-stream-logs) after processing the
batch. Their Endpoint output lane publishes `Actions.Swap`. All returned POSITION
blocks appear in input order, with full-width fields. Empty batches emit an empty
OUTPUT container; a reverted command rolls back its logs. The account is not
included automatically; account context requires a deployment convention.

Use `exec.outputPosition(position)` to append a position and select codes in the
endpoint's output lane to log the final stream. Produced output does not by itself
prove persistence or settlement. An endpoint reporting successful settlement can
use `Actions.Settle`; the emitter remains responsible for the reported semantics.

The legacy `PositionedEvent` and `SettledEvent` mixins and tagged state-log helpers
have been removed. Replay older deployment logs using their original ABI metadata
or the historical tagged formats documented below.

**Flows.** Operations that move value log appropriate amount-bearing blocks through
endpoint lanes or LOG0 streams. Identify the account and include the matching
effect code and the action when known.
In the table below, each listed code occupies a separate uint32 slot; combine them
by widening to uint and shifting, not by OR-ing IDs into the same slot.

| Operation | Action code | Effect code |
| --------- | ----------- | ----------- |
| deposit / depositPayable | `Actions.Deposit` | `Effects.Receive` |
| withdraw | `Actions.Withdraw` | `Effects.Spend` |
| cashout (host implementation) | `Actions.Cashout` | `Effects.Spend` |
| burn | `Actions.Burn` | `Effects.Spend` |
| creditAccount | `Actions.Transfer` | `Effects.Receive` |
| debitAccount | `Actions.Transfer` | `Effects.Spend` |
| payout | `Actions.Payout` | `Effects.Spend` or `Effects.Receive` per account |
| realize | `Actions.Realize` | host-defined |
| final pipeline budget | host posting action | `Effects.Receive` |
| custody locking | per operation | `Effects.Lock` |
| custody release | per operation | `Effects.Unlock` |

`CashoutHook` is abstract and has no event-emitter inheritance. Hosts implementing
cashout are responsible for their flow logging. The free sendChainAsset transfer
helper emits no logs. After a successful payout, a host can log a Balance block
with account-scoped Cashout and Spend codes and documented account identity.

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

**Asset gating.** Hosts that gate assets emit host-scoped Asset block logs from
their allowAsset/denyAsset hooks or equivalent command logging. Pack Entities.Host
first, then Allow and Active or Deny and Inactive. These describe the resulting
support state; publishing a preimage does not change it.

**Opaque assets.** Hosts that create or register opaque asset IDs emit `AssetPreimage`
with the canonical preimage used to resolve the asset. Indexers should treat
`asset` as the ledger key and can verify host-specific opaque IDs by checking
`asset == 0x02 || preimage[1:3] || bytes29(hash(preimage))`. The preimage starts
with `[formatHash][category][subtype]`; `0x01` means keccak256, and the category
must be `Asset`. The rest of the payload is not yet standardized.

**Invocations.** The Pipeline schema records account and initial native-value budget.
Pipeline.pipe emits Entities.Account codes plus this block before its step loop,
including empty pipelines.
The convention is a start log per pipeline invocation with the account
preserved across nesting. Special implementations that change accounts must log
switches and restoration explicitly. Do not sum nested initial budgets as funding.
Deadlines remain an entrypoint concern and are absent from this schema.
The Rooted ABI event and three-field Rooted schema have been removed; decode
historical records using their original formats.

### Codes and Correlation

All events carrying codes use the standard uint packing: up to eight
nonzero uint32 action/entity-kind/effect/state IDs, lowest slot first, with zero-filled unused high
slots. Zero means no codes. Order and duplicates are preserved; adjacency does
not pair actions with effects. Each ID includes its category bits: category 0
is Actions, category 1 is Entities, category 4 is Effects, category 5 is States, and other categories remain reserved.
Actions, Entities, Effects, and States constants already use uint and can be
composed directly with shifts of 32 bits per slot.

Asset and route membership logs (and historical Node/Guardian events) require exactly one occurrence of either
States.Active or States.Inactive. Missing, duplicate, or conflicting membership
state codes violate their convention; indexers must not infer a valid membership
update from such logs. Logging primitives perform no runtime validation, so
emitters are responsible for satisfying the convention. Other code categories
may coexist and retain their ordinary ordering and duplicate rules.

Codes describe the logged operations or outcomes. Asset-flow block logs need
explicit effect codes where the endpoint's documented semantics do not establish
direction or custody changes. Historical Activity logs retain their original
amount/reference interpretation; do not reinterpret them as block streams.

**Shared action semantics.** In every event carrying `codes`, each action ID states
which operation occurred. Its canonical meaning is the same across event types:
`Actions.Create` means creation, `Actions.Delete` means deletion,
`Actions.Add`/`Actions.Remove` mean membership changes, and
`Actions.Refund` means a refund. The event identifies the affected entity or
effect and supplies context. Resulting state codes do not redefine the action. For example,
an Asset block with codes `Entities.Host | (Actions.Create << 32) | (States.Inactive << 64)`
records an asset that was created but is inactive on that host, not a denial.
Consumers should retain the action even when different operations produce the
same state. Hosts choose applicable actions and must emit them truthfully.

| Range | Group | Assigned codes | Reserved |
| --- | --- | --- | --- |
| 0-15 | Lifecycle and membership | None 0, Create 1, Update 2, Delete 3, Add 4, Remove 5, Enable 6, Disable 7, Annotate 8, Introduce 9 | 10-15 |
| 16-31 | Permissions and roles | Authorize 16, Revoke 17, Appoint 18, Dismiss 19, Allow 20, Deny 21 | 22-31 |
| 32-47 | Transfers | Transfer 32, Payout 33, Deposit 34, Withdraw 35, Cashin 36, Cashout 37 | 38-47 |
| 48-63 | Supply | Mint 48, Burn 49 | 50-63 |
| 64-79 | Accounting and settlement | Post 64, Book 65, Realize 66, Settle 67, Fee 68, Refund 69, Credit 70, Debit 71, Bootstrap 72 | 73-79 |
| 80-95 | Trading and credit | Swap 80, Borrow 81, Repay 82, Liquidate 83 | 84-95 |
| 96-111 | Transport | Relay 96, Dispatch 97 | 98-111 |

Values 112 and above are reserved for future groups. Unassigned values must not
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

Joins available to an indexer: documented Pipeline context logs (when emitted) -> invocation account and sibling
logs; `(account, asset)` -> account balance and flow history, including host
accounts. Balance events have no endpoint correlation field.

## Considered And Rejected

These were evaluated and deliberately not proposed:

- **Unconditional duplication of all inputs and outputs.** Endpoint lane codes
  explicitly select meaningful streams for logging. Annotation and access-control
  commands reuse their input blocks instead of constructing duplicate per-item
  events. Reverted calls leave no persisted logs.
- **Unconditional library-forced flow emission for hook-driven commands.** Hosts
  route hooks internally (e.g. a payout hook that calls the credit hook), so
  unconditional emission at that layer would double-count or misattribute.
  Command credit remains in the pipeline budget for the same reason, avoiding
  producer-side events and repeated intermediate settlement.
- **A dedicated event and command for every metadata type.** Entity metadata is
  carried by typed blocks inside `Annotation`, with the generic admin `annotate`
  command publishing later updates.

## Compatibility

AnnotationEvent and its public export are removed. New metadata uses LOG0
ANNOTATION blocks or the annotate endpoint's INPUT batch, without ABI offsets,
topics or an Annotation EventAbi announcement. This is a breaking discovery
change: preload the standard envelope schemas and recognize #label and #schema.
Historical Labeled, Schema and Annotation ABI events retain their deployment's
original formats. Trust and annotation-specific merge rules remain unchanged.

Historical `AccountBalance` and `Balance` ABI events retain their original
deployment-specific layouts. Current balance records use typed blocks with
scoped codes and an explicit account or documented pipeline context. Host
holdings use the deterministic host account.

## Anonymous state logs

This section describes historical logs only. The account-and-codes execution
output overloads and compact/full-width state helpers have been removed. Current
swaps use endpoint-prefixed OUTPUT containers instead. Historical logs describe
produced pipeline values, not proof of persistence or settlement.

These four immutable format tags identify the initial wire format. Future
incompatible formats must use new tags; do not infer a layout from individual
bits. Every identifier (`account`, `asset`, `liability`, `counterparty`) is a full
32 bytes. Integers are unsigned and big-endian. Fields are concatenated with no
ABI offset, length wrapper, block header, or padding.

| Tag | Exact bytes | Fields, in wire order |
| --- | ---: | --- |
| `0x10` | 129 | account, asset, amount:uint256, codes:uint256 |
| `0x11` | 89 | account, asset, amount:uint96, codes:uint96 |
| `0x20` | 225 | account, asset, amount:uint256, liability, debt:uint256, counterparty, codes:uint256 |
| `0x21` | 165 | account, asset, liability, counterparty, amount:uint96, debt:uint96, codes:uint96 |

The tag occupies the first byte and is included in the stated length. Compact
form is selected only if **every** numeric field fits uint96; otherwise all
numeric fields use uint256. Nothing is truncated or saturated. Output blocks
always keep their usual full-width encoding and field order.

Indexers should enable this decoder for known emitting contracts. For a log
with zero topics, require both a recognized first byte and its exact length,
then decode the corresponding layout. Preserve unknown or malformed logs as
raw data. Zero topics alone does not identify a Rootzero state log. Ordinary
historical events retain their ABI/EventAbi decoding. Fetch by emitter address and
block range: these state logs have no event signature or indexed account topics
and cannot be filtered by those fields at the RPC layer. Keep transaction/log
ordering and the normal reorg rollback behavior.

## Correlated block-stream logs

`Logs.stream(correlationId, abs, size)` emits an existing memory block
stream using `LOG0`, with no topics. Its wire format is:

```text
correlationId (32 bytes, highest byte 0x00) | block stream (remaining bytes)
```

`Logs.Stream` is `0x00`. Callers MUST supply a correlation ID beginning with that
byte; the helper emits the ID unchanged without validation or packing. The entire
32-byte word is the correlation ID, with 248 bits available for caller-defined
identity. The tag is part of the ID, not an additional byte. Arbitrary 256-bit IDs
cannot be preserved unless they already start with 0x00.

The stream begins at byte 32; an empty stream is a valid 32-byte log. There is no
ABI wrapper, encoded length, or padding. The caller provides 32 writable bytes
immediately before the stream. The helper saves that word, writes the ID, logs,
and restores the word. It does not copy or validate the stream.

For known participating emitters, dispatch zero-topic logs by their first byte:
`0x10`/`0x11` and `0x20`/`0x21` use the fixed state formats above; `0x00` requires
at least 32 bytes and a well-formed block stream covering the entire remainder.
Preserve unknown tags, malformed streams, and unknown block schemas as raw data.
Application-defined ABI events keep their own decoding path. The library emits no EventAbi.

Scope joins by chain, emitter address, and the complete correlation ID, and apply
normal reorg rollback. Callers decide whether an ID identifies one stream or
several related streams; keep all occurrences in log order. An all-zero ID is
allowed but its application meaning must be defined before joining records.
IDs cannot be filtered as RPC topics; fetch by emitter and decode locally.

## Codes and block-stream logs

`Logs.mem` and `Logs.copy` emit a uniform optional format:

```text
codes (32-byte big-endian uint256) | block stream (remaining bytes)
```

There are no topics or additional tags. A 32-byte log is a valid empty stream.
The full code word is preserved and follows the existing packed-code conventions;
blocks describe the data, while the emitter defines how the codes apply to it.
No account, pipeline context, or correlation ID is inserted automatically.

This format coexists with the existing state and correlation stream formats.
Indexers must select the decoder from an agreed emitter/deployment protocol version
or another unambiguous enclosing convention. Do not guess from the first byte:
valid codes can begin with any existing format tag. New-format emitters should
not mix these undecorated logs with the older tagged formats without an explicit
way to distinguish them. These helpers alone do not migrate existing events or
establish pipeline account inheritance.

For an emitter using this format, require at least 32 bytes, decode the code word,
and validate block framing across the entire remainder. Retain unknown codes or
block keys for forward compatibility. Fetch by emitter, preserve log order, and
apply the same reorg handling as other logs.


## Command runner stream logs

`CommandBase.runCommand(id, descriptor, context, process)` derives logging
selection from nonzero codes in the three published lanes. It emits:

- Before processing: `[endpoint id:32][STATE block and/or INPUT block]` in one
  LOG0 record. Selected blocks include their eight-byte headers, even when empty.
- After processing: `[endpoint id:32][OUTPUT header][output stream]` if output codes
  are nonzero. Empty selected output emits an empty OUTPUT block. The wrapper
  exists only in the event; the returned output remains the original stream.

Resolve the endpoint ID against trusted Endpoint metadata, extract each lane's
codes, and identify STATE/INPUT/OUTPUT by their container headers. Both enabled source
lanes occur in State, Input order. Codes are published in Endpoint metadata,
not repeated in these runtime logs. Disabled lanes emit nothing.

Nested context records occur after the outer context record; nested output
precedes outer output. Callback events occur during processing. Do not assume
context and output records are adjacent. Matching calls across nesting requires
the deployment's execution convention; an ID alone is not a unique invocation ID.
If execution reverts, earlier context logs revert too.

Indexers must use an agreed emitter/deployment convention to recognize runner
records; callback logs must not impersonate them. Codes-prefixed and older
anonymous logs are not universally distinguishable by inspecting the prefix
alone. No universal prefix restriction is enforced by Logs.

These records carry no implicit account or correlation ID. Deployments must
supply any account-context convention separately. Input and output describe
command data, not necessarily persisted balances. Preserve log order and
standard reorg handling.

Swap endpoints select output logging with `Actions.Swap`. Withdraw selects state
logging with `Entities.Account` followed by `Actions.Withdraw`; its Balance spec
identifies the payload without an extra Balance code. Swap and Withdraw publish no
duplicate action annotations. CreditAccount uses Account/Credit (70) on STATE;
DebitAccount uses Account/Debit (71) on OUTPUT. Deposit and DepositPayable use
Account/Deposit on OUTPUT, recording the actual amounts returned by their hooks
without duplicate action annotations. Their Balance specs identify the payloads.
The optimized credit adapter copies arbitrary memory state with `Logs.memCopyWrap`
before its hooks; the debit adapter uses `Logs.memWrap` on its Encoder-owned
output after its hooks. These emit the same ID-prefixed containers as the runners,
including empty batches. Host access commands and the guardian revoke endpoint
also log their scoped INPUT lanes as described above. Other production endpoints
use zero lane codes unless listed below. `runCommandOnce` and `runAdmin`
use the same context/output logging; `runPort` logs INPUT then OUTPUT, and
`runGuard` logs INPUT only. Queries remain view-only and their registration
rejects nonzero lane codes. Custom adapters must call the primitives explicitly.
`Executions.logContext` requires untouched cursors from `openContext`; call it
before consuming either source. It must not be used with `openInput` executions.

Input-only adapters can explicitly call `exec.logInput(id, descriptor)` immediately
following `openInput`, before consuming input. It obeys only the input lane's
logging selection and emits `[id:32][INPUT header][input stream]`. The helper
constructs the missing container header in temporary memory; empty selected input
still emits that header. It preserves execution fields and the free-memory pointer.
Port and guard runners call this helper automatically.


### Additional command operation logs

Account-scoped Cashout, Settle/SettlePayable, Repay, and Burn select STATE logging.
Repay records the original position and debt before clearing debt in returned state.
Burn records the requested balance, not the hook's returned actual-burn quantity.
Payout selects STATE and INPUT: one record contains both containers, with each
balance paired with its recipient at the same index. The recipient does not
replace the source account inherited from the deployment's account context.
Realize selects STATE and OUTPUT, preserving the original counterparty and
obligation alongside the hook-adjusted result. Do not count both as separate flows.
These commands publish their action in lane codes without duplicate action annotations.

AllowAsset/DenyAsset select INPUT with Host/Allow/Active or Host/Deny/Inactive.
Allowance selects INPUT with Host/Update; a zero cap revokes the allowance.
AddPool/RemovePool select INPUT with Host/Pool/Add or Host/Pool/Remove. Their
published pair grouping identifies consecutive assets belonging to each pool;
these records do not independently assert liquidity or pool activation state.

Cashout and Settle's optimized Execute adapters emit the same endpoint-prefixed
STATE container before hooks as their calldata commands, including empty batches.
All source logs revert with a failed operation. Validation and transport commands gain no logging from these changes.

### Cashin of remaining native value

After crediting leftover pipeline value to the account, a host can emit
`Logs.balance(chainAsset, value, Codes.AccountCashin)`. The codes combine
Entities.Account and Actions.Cashin (36); account identity comes from the
pipeline context. The BALANCE amount is the amount actually credited, not the
resulting stored account balance. Skip the log when value is zero. Count this
as one credit, rather than also emitting Account/Credit for the same operation.

### Bootstrap accounting

Bootstrap emits one `[Account/Bootstrap codes][BALANCE stream]` after all debit
hooks complete. Non-native requests appear in request order, including zero
amounts, followed by the combined actual chainAsset debit if nonzero. Zero
non-native entries describe a zero delta and do not invoke debit hooks. Account
identity comes from the deployment's pipeline context. A log is omitted only
when there are no non-native requests and no native debit. The endpoint INPUT
lane has no log codes.

This zero-inclusive policy differs from v1.50.0, which omitted zero entries.
Consumers must accept zero deltas and must not infer that a Bootstrap log implies
a nonzero debit or one hook call per block. Output count, order and requested
amounts are unchanged; native requests still aggregate into one actual debit.

Assigned value may cover requested chainAsset balances and the budget. Only the
uncovered native amount appears in the log; native request splits, zero native
amounts and the budget itself are not logged. Indexers apply every emitted Balance as a debit;
there is no separate Account/Debit record to combine or override. Deployments
using the earlier INPUT-log policy must be decoded according to their version.

Budget is the minimum credit remaining after balances are funded. For requests
of 3 and 4 chainAsset, budget 5, and assigned value 4, output contains balances
3 and 4, returned credit is 5, and the single actual chainAsset debit is 8.
All logs revert if any funding operation fails. The former fixed Bootstrap
payload and additive per-item budget semantics require deployment-version-aware
decoding and must not be used for this schema.

### Bootstrap shared output and reserved log space

The current implementation validates the outer BOOTSTRAP and final LIST together,
then validates each exact ASSET_AMOUNT header in one processing pass. It reserves
`[output:size][writable log prefix:32][log capacity:size + 72]` before hooks run.
The output retains its own bytes-length word and Encoder leading word. Its logical
padding is cleared separately after shortening the larger allocation. The private
forkLog helper accepts only this layout and copies only the initialized prefix.
Native funding and checked arithmetic are unchanged; zero-amount hooks remain skipped.
Scalar Pipeline and Balance logs use temporary memory without advancing the allocator.
There is no asset pre-scan, loop unrolling, or singleton path.

The Commander reference used Solidity 0.8.33/Osaka. These upstream measurements
use **Solidity 0.8.35, viaIR, optimizer 200, Cancun** with identical inputs and
compiler settings for all three variants. The stock adapter and scalar log helpers
are frozen from v1.50.0. The zero-inclusive reference retains the stock decoder and
allocation, includes zero non-native entries, skips zero hooks, and uses the same
new scalar log helpers. This isolates implementation savings from the event policy.

| Balances | Cases | Receipt gas saved vs zero-inclusive | Mean saving | Positive-request saving vs stock |
|---|---:|---:|---:|---:|
| 1 | 37 | 212 to 404 | 332.0 | 376 to 654 |
| 2 | 83 | 262 to 496 | 442.4 | 460 to 765 |
| 3 | 169 | 314 to 591 | 539.8 | 548 to 880 |
| 4 | 353 | 370 to 692 | 641.1 | 638 to 1000 |

All **642** short-list cases improve against the same-policy reference; the
unweighted mean saving is **570.94 gas**. There are **177 regressions versus stock**,
all in zero-containing scenarios whose log contents intentionally differ. Worst
extra receipt gas versus stock is 431/890/1,346/1,796 for 1/2/3/4 balances.
Every positive-amount scenario improves versus stock.

An additional 18 scenarios cover 0/5/8/15/32/128 entries in native, non-native and
mixed layouts. All improve against the zero-inclusive reference, by 320 to 11,967 gas.
The 32- and 128-entry non-native cases cost 595 and 3,648 more gas than stock due
to retained zero entries. These samples are correctness and gas checks, not an
exhaustive performance guarantee for arbitrary larger lists or hook implementations.

Runtime bytecode in the identical ledger test harness is **3,325 bytes**, versus
**3,945** for stock and **3,868** for the zero-inclusive reference: reductions of
620 and 543 bytes. These are harness sizes, not Commander deployment sizes.
The original patch was adapted to preserve zero-hook skipping, zero output padding
and InvalidBlock for reversed cursors. Consolidating the framing checks also
removed regressions observed in the first upstream adaptation.

The benchmark performs Bootstrap/credit/cashin ledger roundtrips using real assigned
native value. It checks exact returned output and credit, all five ledger balances,
hook counts, exact logs, native custody and caller wallet changes including fees.
The common harness includes a hook-call counter and output-padding assertions;
absolute gas is not a prediction for a specific deployed host. It does not perform
ERC-20 transfers or swaps. The matrix covers all 30 native/non-native orderings,
budgets 0/9, absent/partial/exact/excess assigned value, positive/alternating-zero/
all-zero amounts, and repeated non-native assets. Dirty-memory and allocating-hook
checks run separately so they do not distort the gas comparison.

Release validation: 2,214 tests including all benchmarks; 431 differential
malformed/funding cases; 100 dirty-memory scenarios across all three variants;
explicit rollback, reversed-cursor, full-width, padding and scalar allocator checks;
and TypeScript checking. The existing authorization and reentrancy paths are unchanged.

Raw measurements, including per-case execution gas and receipt gas, are saved in
[BOOTSTRAP_SHORT.json](benchmarks/BOOTSTRAP_SHORT.json). Reproduce with:

```sh
npm run bench -- test/bootstrap-short.bench.test.ts
npm test
npm run typecheck
```

The benchmark writes its fresh capture to `.npm-cache/bootstrap-short-matrix.json`.

### Commander event migration benchmarks

Historical measurements before adoption of the lazy hybrid below.
Measured 2026-10-05 with solc 0.8.35, viaIR, optimizer 200, Cancun bytecode,
and the repository's Hardhat EDR network. The reference is Commander Main.sol /
Base.sol and its installed rootzero contracts 1.48.0. No Commander files changed.

Two benchmarks separate the effects:

- `commander-logs.bench.test.ts`: 44 workloads compare the exact legacy Balance,
  Activity and Rooted event signatures against block logs, with identical current
  funding, decoding, output allocation and ledger operations. A no-log control
  measures incremental logging cost. Counts include 0/1/2/4/8/16 requests,
  distinct non-native assets, repeated native assets, funded native requests,
  cashin and the root record. The combined flow is Bootstrap -> creditAccount ->
  cashin, including Rooted/Pipeline account context.
- `commander-bootstrap.bench.test.ts`: 15 paired cases compare the installed 1.48
  Bootstrap algorithm, fixed input codec, original allocator and Main debit hook
  against the actual current ExecuteBootstrap. It includes decoding, allocation,
  native debit aggregation and changed input encoding as well as logging.
  A final budget contribution of 5 with no assigned value makes unfunded cases
  equivalent. Funded cases use budget zero and assigned value 10 * count + 5.
  These inputs produce identical outputs, credits and final ledger balances.

All event payloads, event counts, outputs and affected ledger balances are
asserted. Accounts start with nonzero balances; each call starts with fresh
transaction access warmth. Repeated native assets become warm within a call.
The tables report internal gasleft differences, excluding external ABI encoding,
intrinsic transaction gas, refunds, deployment and metadata publication. Receipt
gas is also saved in the JSON reports, including calldata cost and the network's
transaction gas rules. These are focused harness results, not complete deployed
Main transaction estimates: authorization, dispatch, transfers and deadline checks
are outside this measurement. Legacy snapshots become scoped deltas; indexers need
pipeline context and the new decoding rules to reconstruct balances.

Positive numbers below are gas saved; negative numbers are extra gas.

| Logging-only workload | 1 request | 4 requests | 16 requests |
|---|---:|---:|---:|
| Credit | 325 | 3,678 | 17,080 |
| Debit | 339 | 3,756 | 17,424 |
| Bootstrap / credit / cashin, non-native | 3,161 | 9,916 | 36,903 |

Cashin saves 2,279 gas: one Balance block replaces Balance + Activity.
The Pipeline record saves 285 gas versus Rooted, with no deadline field.
Empty selected lanes cost more because the old hooks emitted nothing.

| Bootstrap adapter migration | 1 request | 4 requests | 16 requests |
|---|---:|---:|---:|
| Non-native requests + native budget | -250 | 3,547 | 18,725 |
| Native requests + budget, unfunded | -1,913 | 3,579 | 25,537 |
| Native requests entirely funded by assigned value | -2,100 | -3,322 | -8,208 |

For unfunded non-native requests, savings start at two requests. For repeated
unfunded native requests, two requests still cost 81 extra gas; the tested four-item
batch saves gas. Fully funded native requests cost more execution gas because
Main previously emitted no debit events, while the new adapter always records
Bootstrap input. Smaller calldata offsets part of this increase in receipt gas.

Run the focused comparisons with:

```sh
npm run bench -- test/commander-logs.bench.test.ts test/commander-bootstrap.bench.test.ts
```

Full measurements are written to `.npm-cache/commander-logs-gas.json` and
`.npm-cache/commander-bootstrap-gas.json`. Construction/discovery events are
excluded from the measured transactions. No production event policy is changed
by these benchmark fixtures.

### Bootstrap actual-debit writer experiment

Measured 2026-10-05 with the same compiler/network settings as the Commander
comparison above. `bootstrap-debit-logs.bench.test.ts` originally compared input-logging
Bootstrap against two test-only candidates with identical funding, checked sums,
output allocation and ledger hooks. That input logger is now a frozen baseline. The hybrid comparison also uses
frozen v1.50.0 behavior; the current zero-inclusive candidate has a separate
`bootstrap-short.bench.test.ts` matrix.

Both candidates reserve space for `request count + 1` Balance blocks before
processing requests. They append each nonzero non-native debit and, last, the
combined native debit if nonzero. They emit a single AccountBootstrap-prefixed
Balance stream after hooks, and emit nothing when there are no actual debits.
This changes the event semantics from requests plus a separate native debit to
actual debits only; request splits, zero amounts and funding supplied by assigned
value are deliberately absent from the candidate log.

- **Writer:** Encoder.init, writeBalance, finish and Logs.mem. Upfront capacity
  covers the worst case; no resizing is needed.
- **Reserved:** Encoder.allocate, writeBalanceAt and Logs.mem over the written
  range. The complete upper bound is reserved once; unused capacity is never
  exposed or logged. No finish step is needed for this event-only buffer.

Forty-two scenarios cover 0/1/2/4/8/16/32 requests: distinct non-native assets
with/without a budget shortfall, repeated native requests, fully funded native
requests, alternating native/non-native requests, and zero quantities. Every
variant is checked for exact output, returned credit, affected ledger balances,
log count and full log contents. Amounts are 10, budget is 5 except no-budget
and zero cases, mixed cases receive value 7, and fully funded cases receive
native requested total + budget. Storage starts nonzero and access warmth resets
for each call. Tests capture receipt gas separately from internal gasleft totals.

Positive values are execution gas saved versus the previous INPUT/native-debit logging;
negative values are additional gas. Results include allocation and encoding.

| Workload | Writer: 1 request | Writer: 4 | Writer: 16 | Reserved: 16 |
|---|---:|---:|---:|---:|
| Non-native + budget debit | 504 | -222 | -3,118 | -1,843 |
| Non-native, no budget debit | -54 | -774 | -3,669 | -2,513 |
| Native, account-funded | 1,308 | 2,998 | 9,767 | 9,565 |
| Native, fully funded by assigned value | 1,450 | 3,143 | 9,913 | 9,613 |
| Alternating native/non-native | 1,308 | 1,389 | 3,325 | 3,861 |
| Zero quantities, no budget | 1,449 | 3,139 | 9,897 | 9,325 |

The one-request mixed case contains only native asset. Native-heavy batches win
because repeated requested native balances collapse into one actual debit block,
or no block when fully funded. Mixed batches also emit fewer bytes. Non-native
batches still emit nearly all the same quantity data and must construct another
stream, so their per-item writer cost can exceed the saved framing/log overhead.
The reserved writer reduces that cost, but does not remove the regression for
large all-non-native batches. The ordinary writer can be cheaper when little is
written: its unused capacity need not all be touched, while Encoder.allocate
writes the trailing zero word at the reserved end.

```sh
npm run bench -- test/bootstrap-debit-logs.bench.test.ts
```

The complete results, including 32-item cases, log bytes and receipt gas, are in
`.npm-cache/bootstrap-debit-logs-gas.json` after running the benchmark.

### Bootstrap lazy hybrid writer experiment

The hybrid is now the production implementation, tested through
`CommanderCurrentBootstrap` against the frozen `CommanderInputBootstrap` and
two eager writer candidates across 70 scenarios. It retains the
output as the event source until the first native request or zero amount that
must be excluded. At that point it allocates space for request count + 1 Balance
blocks, copies only the already-written output prefix, and appends later actual
debits. If no exclusion occurs, it logs the output directly; a final budget-only
native debit forces allocation/copy only at the end. The output buffer itself is
never repurposed, resized or mutated by event construction.

The extension adds native-first, native-last, zero-first and zero-last batches.
All variants still check exact output, credit, ledger balances and event bytes.
The compiler/settings, storage setup and measurement boundaries are unchanged.
These measurements precede the later cursor and branch cleanups. Rerunning the
benchmark measures current production; frozen candidates retain the earlier code.

Positive values are execution gas saved versus the previous direct INPUT log
plus any separate native debit event; negative values are extra gas.

| Hybrid workload | 1 request | 4 requests | 16 requests | 32 requests |
|---|---:|---:|---:|---:|
| Non-native + budget debit | 646 | 463 | -270 | -1,247 |
| Non-native, no budget debit | 355 | 215 | -347 | -1,083 |
| Native, account-funded | 1,137 | 2,706 | 8,990 | 17,369 |
| Native, fully value-funded | 1,214 | 2,786 | 9,070 | 17,449 |
| Alternating native/non-native | 1,137 | 1,394 | 3,742 | 6,873 |
| One native request first | 1,137 | 738 | -850 | -2,967 |
| One native request last | 1,137 | 951 | 218 | -759 |
| One zero amount first | 1,180 | 26 | -1,562 | -3,679 |
| One zero amount last | 1,180 | 239 | -494 | -1,471 |

The hybrid reduces duplicate encoding but still carries per-item tracking and
branch costs. At 16 non-native requests plus budget, it costs 270 extra gas versus
the input logger, compared with 3,118 extra for the ordinary writer and 1,843 for the
fully reserved writer. Without a budget debit, that penalty falls from 3,669
(ordinary writer) to 347 (hybrid). Small all-non-native batches now save gas.

Late exclusions allow a large prefix to be copied once; early exclusions still
require writing most later entries into the separate buffer. A 16-item batch
with native first costs 850 extra gas, while native last saves 218. Entirely
native batches still save substantially versus the input logger, but the simpler
ordinary writer is cheaper than the hybrid for those cases. Zero-only batches
emit no event and also save gas. This is a workload-dependent tradeoff; the hybrid was adopted to prioritize
small batches and avoid logging requested amounts as if they were debits.

Reproduce with the same `bootstrap-debit-logs.bench.test.ts` command above. The
JSON report now includes hybrid execution gas, receipt gas and log counts.

### Bootstrap small-call optimization follow-up

Before the later grouped-branch cleanup, two further test-only candidates
were compared against production with the same compiler and ledger setup.
`bootstrap-small-call.bench.test.ts` checks 70 scenarios for identical output,
credit, ledger balances and complete event data.

Positive numbers are gas saved relative to production; negative numbers are extra gas.

| Workload | Single-request shortcut | Deferred empty-prefix allocation |
|---|---:|---:|
| One non-native request, no budget debit | -343 | -54 |
| One non-native request + budget debit | -439 | -143 |
| One native request + budget debit | 130 | 223 |
| One fully value-funded native request | 119 | 121 |
| Two mixed requests | -231 | -184 |

Neither candidate was adopted. The shortcut adds branches and repeated decoding;
the deferred writer needs an extra cursor state and allocation checks. Their
native-only improvements do not justify regressions in common small non-native
and mixed calls. Production remains the simpler hybrid implementation.

Run `npm run bench -- test/bootstrap-small-call.bench.test.ts`; complete results
are written to `.npm-cache/bootstrap-small-call-gas.json`.
