# Multi-Chain Port Analysis

## Context

Rootzero is currently an EVM Solidity protocol/library. The goal of the port is to keep the same protocol ideas - hosts, access control, commands, peers, pipelines, balances, and block streams - while letting each supported chain implement those ideas with its own native primitives.

The shared interface is the block wire format:

```text
[bytes4 key][uint32 len][payload]
```

A STEP block stream has the same meaning whether it is parsed by an EVM contract, a Solana program, a CosmWasm contract, or a NEAR contract. That shared byte format is the portable part.

The important design constraint is that a chain runtime should not need to know about any other chain. There should be no global chain ID registry in the portable libraries, no Solana code that knows Cosmos identifiers, and no CosmWasm code that needs EVM chain IDs.

The cross-chain shape is:

1. A bridge or messaging layer moves raw bytes to another chain.
2. Those bytes are Rootzero CONTEXT blocks.
3. The destination chain has a local host exposing a port pipe entrypoint.
4. That host unpacks the CONTEXT blocks and runs the normal local `pipe()` loop.

The bridge knows how to deliver bytes to the destination chain, but Rootzero core does not need to know how the bridge routes them. Once bytes arrive at a destination host, the host interprets them as local Rootzero protocol data.

## Design Principles

1. **Stay protocol-native by default.**
   Rootzero IDs, block streams, balances, command contexts, and transaction records should stay in Rootzero protocol form for as long as possible. Chain-native addresses, accounts, token handles, and call formats should appear only at adapter boundaries where the local runtime actually requires them.

2. **The block stream is portable; execution is local.**
   A pipeline delivered to Solana runs as a Solana-local pipeline. A pipeline delivered to EVM runs as an EVM-local pipeline. The common block stream lets bridges and tooling move the same payload shape between hosts, but a destination host dispatches only local steps.

3. **No global chain IDs in portable IDs.**
   Existing EVM IDs include `block.chainid` for EVM-local safety. Non-EVM ports should not introduce a `ChainIds.sol`-style registry or a cross-chain numeric namespace. Each chain library only needs its own local ID constructors and validators.

4. **Use one ID convention.**
   `0x00` is reserved for null/unset IDs. Account, asset, and node IDs whose
   first byte is `0x02` are opaque
   `[0x02][category][subtype][bytes29(hash)]` handles. Resolve them with local
   lookup or witness data only when native metadata is needed.
   Other assigned representation bytes identify their structured layout.

5. **Routing metadata lives outside Rootzero core.**
   A bridge may keep a route like `(destination chain, destination bridge endpoint, destination host, raw payload)`, but the destination chain handle is not part of the command IDs inside the CONTEXT payload. When the destination host receives the input, each STEP command is already a local command ID for that host's runtime.

6. **Each chain owns its native identity model.**
   EVM uses addresses and ABI selectors. Solana uses program IDs, accounts, and instruction discriminators. CosmWasm uses contract addresses and execute message variants. NEAR uses account IDs and method names. The shared protocol should not force those into a global foreign-chain shape.

7. **Foreign references are transport data, not dispatch authority.**
   If a bridge needs to prove source chain, source sender, nonce, or delivery path, that belongs to the bridge adapter or application-level record. Core host dispatch and access control should authorize the local bridge/peer caller and local trusted nodes only.

8. **Every port must choose an identity strategy.**
   EVM can fit node and account addresses directly inside Rootzero IDs. Some chains cannot. If a native address fits, the port can decode it directly from the ID. If it does not fit, the ID is a compact handle. The host should still use that ID as the protocol key, and only resolve it at the edge where a native address is actually required.

---

## What Is and Is Not Portable

### Chain-Agnostic

| Component | Files | Porting note |
|-----------|-------|--------------|
| Block wire format | `codec/Schema.sol`, `codec/Keys.sol` | Pure binary TLV. Re-implement exactly per language. |
| Cursor parsing | `codec/Decoders.sol` | Zero-copy byte stream reader. Re-implement per language. |
| Writer helpers | `codec/Writers.sol` | Block stream builder. Re-implement per language. |
| Block key constants | `codec/Keys.sol` | `bytes4(keccak256("#name"))`; portable to any keccak library. |
| Pipeline state model | `core/Pipeline.sol` | STEP stream and threaded `bytes` state. Local execution, dispatch, and posting are chain-specific. |
| TRANSACTION schema | `core/Types.sol` | Abstract `(from, to, asset, amount)` ledger model. |
| Balance ledgers | `core/Balances.sol` | One `map(account => map(asset => amount))`, including host accounts; map to any key/value store. |
| Command/Port/Query/Guard roles | `commands/`, `ports/`, `queries/` | Same logical roles, expressed with local call primitives. |
| Port pipe input shape | `ports/Pipe.sol`, `codec/Schema.sol` | CONTEXT blocks carry `(account, state, input)`; the input bytes are a STEP stream. |
| Access control model | `core/Access.sol` | Commander, trusted nodes, and guardians. Identities are local. |

### Chain-Specific

| Component | EVM form | Non-EVM form |
|-----------|----------|--------------|
| Node IDs | Type prefix + `block.chainid` + ABI selector + address | Local node prefix + local dispatch tag + local address/program/contract fingerprint. |
| Asset IDs | Native value, ERC-20, or opaque hash handles | Native token, SPL Token, IBC denom, CW20, NEP-141, or opaque hash handles. |
| Account IDs | Admins are EVM chain-local; users can be chain-unspecified; guardian is a role on a user account | Chain-native signer/account identity or opaque account commitment. |
| ID resolution | Address is recoverable from the ID when needed | Use IDs as protocol keys; recover or look up native identities only at native call/transfer boundaries. |
| Auth proof | secp256k1 ECDSA via `ecrecover` | ed25519, secp256k1, account abstraction, or native signed transaction context. |
| Dispatch | `abi.encodeWithSelector` + EVM `call()` | Anchor instruction/CPI, CosmWasm `WasmMsg::Execute`, NEAR promise/cross-contract call. |
| Native value | `msg.value` / ETH | Lamports, native Cosmos denom, yoctoNEAR, or chain-specific value model. |
| Caller identity | `msg.sender` | Native signer/caller as exposed by the runtime. |
| Host identity | `address(this)` | Program ID, contract address, account ID, or another native host handle. |
| Bridge delivery | External bridge calls local peer | Local bridge adapter authenticates delivery and calls local port pipe entrypoint. |

---

## ID Model

The current Solidity layout is:

```text
[255:224] uint32 type prefix
[223:192] uint32 EVM chain id
[191:160] uint32 ABI selector
[159:0]   uint160 EVM address
```

That layout is appropriate for EVM because `block.chainid`, ABI selectors, and 20-byte addresses are native EVM concepts. It should remain the EVM implementation detail.

EVM account and ERC-20 asset IDs use the same address position, bits `[159:0]`.
Their encoders leave the middle four bytes, bits `[191:160]`, zero instead of
storing a selector. Address extraction therefore uses the low 160 bits for all
these EVM ID categories after the appropriate representation and category checks.

For portable ports, the ID model has two forms. Opaque IDs are:

```text
[255:248] 0x02
[247:240] category
[239:232] subtype
[231:0]   bytes29(hash)
```

Use opaque IDs when the native identity or metadata does not fit or should not
be exposed. The full preimage must be supplied by local lookup or by witness
data at the boundary that needs it.

Opaque preimages start with:

```text
[formatHash:1][category:1][subtype:1][payload...]
```

`0x01` means keccak256. Category and subtype are included in the hash and copied
into the ID, binding its visible type to its opaque identity. The remaining
payload format is host/domain-specific until a future standard defines it.

Structured IDs keep the Rootzero prefix taxonomy and make the payload
local-first:

```text
[255:224] uint32 shared type prefix = [representation:8][category:8][subtype:8][flags:8]
[223:192] uint32 local domain / reserved field
[191:160] uint32 dispatch tag
[159:0]   uint160 local identity fingerprint
```

The category and subtype bits are protocol-wide for structured and opaque IDs. Accounts
from any chain should carry the `Layout.Account` category bit. Nodes from any
chain should carry the `Layout.Node` category bit. Assets from any chain should
carry the `Layout.Asset` category bit. Opaque IDs expose these two classification
bytes while keeping the underlying native identity hash-backed.

In the EVM Solidity implementation, helpers should validate the full
representation-specific family rather than only the shared category byte:

```solidity
function isEvm(bytes32 account) internal pure returns (bool) {
    return isFamily(uint(account), Family);
}
```

That keeps EVM deconstruction helpers honest: they only accept IDs whose
payload layout is actually EVM-compatible. Cross-chain ports can expose their
own representation-specific helpers while preserving the same Account, Node,
and Asset taxonomy where it applies.

The representation byte describes how an ID payload should be interpreted.
`0x00` is reserved, `Layout.Rootzero` (`0x01`) identifies protocol-native
structured IDs, `Layout.Opaque` (`0x02`) identifies hash-backed IDs, and
`Layout.Evm` (`0x03`) identifies EVM IDs whose payloads are built around
20-byte addresses. Non-EVM ports should define chain-appropriate representation
tags, such as `Solana`, `CosmWasm`, or `Near`, while still keeping the
same `Account`, `Node`, `Asset`, `Admin`, `User`, `Host`,
`Command`, `Port`, `Query`, and `Guard` taxonomy where it applies. Endpoint
behavior such as handoff is carried in the shared flags byte.

The bits after the shared prefix are chain-specific. The `local domain / reserved field` is not a global chain ID. A chain can set it to zero, a host-local namespace, a deployment generation, or another local-only value if useful. No library should maintain constants like `SOLANA_MAINNET`, `COSMOS_HUB`, or `NEAR_MAINNET`.

Examples:

```text
EVM user account:
[Evm][Account][User][local/account payload with EVM address]

Solana user account:
[Solana][Account][User][local handle/fingerprint payload]

CosmWasm user account:
[CosmWasm][Account][User][local handle/fingerprint payload]

EVM command node:
[Evm][Node][Command][EVM chain/local field][ABI selector][address]

Solana command node:
[Solana][Node][Command][local field][instruction tag][program fingerprint]
```

### Local ID Construction

Each chain gets its own `ids` module:

| Chain | Local constructor examples |
|-------|----------------------------|
| EVM | `toHost(address)`, `toCommand(name, address)` |
| Solana | `to_host(program_id)`, `to_command(discriminator, program_id)` |
| CosmWasm | `to_host(contract_addr)`, `to_command(message_tag, contract_addr)` |
| NEAR | `to_host(account_id)`, `to_command(method_tag, account_id)` |

The constructors only need local data. If an identity does not fit in a
structured ID payload, use an opaque
`[0x02][category][subtype][bytes29(hash)]` ID and store the
full native identity in local host state, or require it as witness data when it
is used. Any registry is chain-local; it is not a directory of other chains.

The constructors should not invent new category meanings. A chain-specific
account constructor still returns an ID with the shared Account category. A
chain-specific command constructor still returns an ID with the shared Node
category and Command subtype, copying its endpoint flags into the final type
byte. The chain-specific part is the representation tag and payload, not the
high-level protocol meaning.

### Inline vs Lookup-Backed IDs

This is one of the first decisions for every chain port.

On EVM, node and account IDs are self-describing enough for local use:

```text
node id -> lower 160 bits -> EVM address
account id -> payload bits -> EVM address or opaque account commitment
```

That means helpers like `Nodes.addr(id)` can recover the call target directly from the ID.

Non-EVM ports should classify each native identity type:

| Identity | Fits in ID payload? | Strategy |
|----------|---------------------|----------|
| 20-byte EVM address | Yes | Store directly in the ID. |
| 32-byte Solana pubkey | No | Store an opaque ID with the appropriate category/subtype; resolve by local lookup or witness. |
| CosmWasm `Addr` string | Usually no | Store an opaque Account ID; resolve to the validated local `Addr`. |
| NEAR `AccountId` string | No | Store an opaque Account ID; resolve to the local account ID string. |
| IBC denom / long asset key | No | Store an opaque Asset ID; resolve to the denom/contract in local asset state or witness. |

Lookup-backed IDs are still local IDs. The lookup table belongs to the destination host or chain adapter and only contains identities meaningful on that chain.

Most protocol logic should not resolve them. Balances, block streams, command contexts, transaction records, and state threading should use the account/node/asset ID exactly as encoded. The ID is the canonical protocol identity. In other words: stay protocol-native until a native chain operation forces conversion.

The required local operations are:

```rust
fn node_id(native: NativeNodeIdentity, tag: DispatchTag) -> LocalNodeId;
fn account_id(native: NativeAccountIdentity) -> AccountId;
fn asset_id(native: NativeAssetIdentity) -> AssetId;

fn resolve_node(id: LocalNodeId) -> Result<NativeNodeIdentity>;
fn resolve_account(id: AccountId) -> Result<NativeAccountIdentity>;
fn resolve_asset(id: AssetId) -> Result<NativeAssetIdentity>;
```

Ports where identities fit can implement the resolve functions by decoding the ID. Ports where identities do not fit must implement the resolve functions with local storage.

Resolution should be lazy and limited to the native boundary:

- `dispatch(target, ...)` resolves `target` only when it needs the local callable node address/program/account.
- access control stores trusted local node IDs; it resolves only when comparing a native caller to an encoded local node identity requires it.
- balance storage uses `account` and `asset` IDs as keys without resolving account addresses.
- posting uses the account IDs from TRANSACTION blocks as ledger identities without resolving them.
- asset hooks resolve asset IDs only when they need to perform native token transfers.
- account hooks resolve account IDs only when the native runtime requires the full address, pubkey, or account string, such as paying out to a local token account.

On EVM, depositing ERC-20 tokens is the canonical example: the protocol balance is credited to `bytes32 account`, but the hook may need an actual local address to perform or verify the token movement. That native-address step belongs in the hook, not in the balance ledger.

Do not add foreign-chain lookup here. A Solana host may resolve Solana pubkeys; it should not resolve EVM addresses or Cosmos addresses unless those are explicit application data outside core dispatch.

### Dispatch Tags

The 32-bit dispatch tag is interpreted by the local runtime:

| Chain | Dispatch tag |
|-------|--------------|
| EVM | ABI selector |
| Solana | Anchor instruction discriminator prefix or explicit command tag |
| CosmWasm | Stable tag for an `ExecuteMsg` variant |
| NEAR | Stable tag for a method name |

The tag is not globally unique. It only needs to be unambiguous inside the local host/command runtime.

### Chain-Native Asset Helpers

Ports should not recreate EVM-specific helpers like `erc20()`, `toErc20()`, or
`matchErc20()` unless the target chain actually has EVM/ERC assets.

The pattern to port is:

- keep the shared `Layout.Asset` category for all asset IDs
- define local asset subtype tags for the target chain's asset model
- construct asset IDs from native asset identities, using opaque
  `[0x02][Asset][subtype][bytes29(hash)]` IDs when the native key does not fit
- resolve asset IDs only inside asset hooks when native transfers require it

The shared asset subtype assignments are `Derived = 0x01`, `Virtual = 0x02`,
and `Erc20 = 0x03`. Derived and Virtual are reserved taxonomy values without
dedicated helpers or standardized subtype-specific payloads. A port should not
infer issuance or redemption behavior from these reserved values.

Examples:

| Chain | Helper examples |
|-------|-----------------|
| EVM | `toChain()`, `toErc20(address)` |
| Solana | `to_native_sol()`, `to_spl_mint(pubkey)`, `to_token_account(pubkey)` if token accounts are represented separately |
| CosmWasm | `to_native_denom(denom)`, `to_cw20(contract_addr)`, `to_ibc_denom(denom)` |
| NEAR | `to_native_near()`, `to_nep141(account_id)` |

The names do not need to match the EVM helper names. The behavior should match
the protocol role: build a stable asset ID, recognize structured assets through
the shared Asset category when available, and resolve to the native token
representation only when an adapter performs native movement.

### Bridge Route References

A bridge or off-chain orchestrator can still describe a multi-chain delivery, but it should keep route metadata outside the CONTEXT block stream:

```ts
type RouteRef = {
  chain: "evm:1" | "solana:mainnet" | "cosmos:osmosis-1" | string;
  host: string;
  localNodeId: bigint;
};
```

`chain` and `host` are transport concerns. The submitted Rootzero payload is still just CONTEXT blocks. Inside those contexts, STEP commands are local command IDs for the destination host.

This keeps the core libraries simple: Solana code does not parse EVM chain IDs, and EVM contracts do not need a registry of Solana network constants.

---

## Bridge Delivery Model

The bridge is a byte transport. It does not need to understand Rootzero internals beyond "deliver this payload to that host/entrypoint".

On the source side:

1. Build a CONTEXT block stream.
2. Each CONTEXT block contains `(account, state, input)`.
3. Each nested `input` value is a STEP block stream whose commands are local IDs on the destination host.
4. Submit the raw CONTEXT bytes to the bridge with whatever destination metadata the bridge requires.

On the destination side:

1. The bridge endpoint verifies the bridge message using its own security model.
2. The destination portal forwards the raw CONTEXT bytes to its commander
   host's port pipe entrypoint. The commander is fixed by portal deployment;
   ordinary delivery does not select an arbitrary destination port.
3. The host checks that the local caller is trusted, just like `PortBase.onlyPeer` does on EVM.
4. The host unpacks each CONTEXT block and threads the remaining budget through
   `budget = pipe(account, state, input, budget)`.
5. `pipe()` dispatches local STEP commands exactly like a same-chain pipeline.

A trusted peer is a fully trusted extension of the receiving host. Admission
authorizes every exposed port, without separate peer-specific permissions for
ports, assets, directions, or operations. The runtime authenticates the peer
once at port entry rather than repeating authorization for each batch item.

Before admission, maintainers must fully validate the peer's behavior, caller
validation, dependencies, and upgrade authority against the receiving host's
invariants. A peer must prevent untrusted callers or incoming bridge messages
from causing invalid actions through its trusted access. Changes require renewed
validation of that trust decision. Partially trusted components must not be
admitted as peers. Parsing and accounting invariants remain enforced; they are
operation-validity checks, not a second peer authorization layer.

In EVM today, the entrypoint is:

```solidity
function portPipePayable(bytes calldata input) external payable onlyPeer returns (bytes memory, uint)
```

The non-EVM ports should provide the same logical endpoint, even if the native name differs:

```rust
fn peer_pipe(input: &[u8], attached_value: NativeValue) -> Result<(Vec<u8>, NativeValue)>
```

Ports return output bytes and trusted native budget credit. The EVM dispatch
port returns its unspent budget; the pipeline port settles its remainder through
`cashin` and returns zero credit. Returning credit is accounting,
not an automatic native transfer back to the caller.

The bridge adapter is the only component that cares about remote chain identity. The host only sees a trusted local caller and a byte payload.

If ordinary forwarding fails, the portal records the message digest under its
recovery key. Recovery may deliberately select a different trusted port instead
of the commander's pipe endpoint, allowing transports to provide specialized
error handlers without making the normal delivery path configurable.

### Context Payload Shape

The destination payload is:

```text
context {
  bytes32 account,
  #bytes state,
  #bytes input     // STEP block stream for pipe execution
}
```

Multiple CONTEXT blocks can be batched in one bridge message. They share the peer call's value budget and execute independently through the same host pipeline.

Important consequence: command IDs inside the nested STEP stream are destination-local. The source chain does not need to understand them, and the destination chain does not need to understand where the bytes came from beyond trusting the bridge adapter.

---

## Blueprint Repository

Use the Solidity implementation as the canonical blueprint:

```text
https://github.com/lastqubit/rootzero-contracts
```

For a blank-project CosmWasm port guide, see:

```text
docs/cosmwasm-port-blueprint.md
```

Ports should copy the behavior, wire formats, ID taxonomy, command semantics, and failure cases from this repository rather than inventing parallel rules.

Ports should also mirror the EVM protocol structure as closely as the target runtime reasonably allows. The Solidity contracts are the blueprint for module boundaries and responsibilities: access control stays access control, pipeline execution stays pipeline execution, port pipe stays port pipe, and asset hooks stay adapter hooks.

This is not a requirement to copy inefficient EVM mechanics. If mirroring the Solidity shape would cause a large performance, storage, compute, or fee penalty on the destination chain, prefer the native-efficient implementation. Preserve the externally visible protocol behavior, wire format, ID taxonomy, authorization rules, and test outcomes; optimize the internal structure where the chain requires it.

### Strict Protocol Parity Rule

The Rootzero block wire format is chain agnostic. For every protocol surface copied from the original EVM library, a port must parse the same block input bytes and produce the same block output bytes wherever the EVM library defines wire input or output.

This applies to all:

- commands
- peer operations
- admin operations
- guards
- queries

Chain-specific behavior may differ only at adapter boundaries, such as:

- native token transfer mechanics
- account/address resolution
- CosmWasm messages vs EVM calls
- storage backend details
- signature verification APIs

These differences must not change protocol block semantics. A port can translate native execution details, but it must not translate Rootzero blocks into a different protocol shape.

Implementation guidance:

- Wire handlers through a shared host/registry dispatch path, not only through chain-specific execute/query entrypoints.
- Tests must assert byte-level parity for command/query outputs and exact accepted block input schemas for peers, admins, and guards.
- Discovery metadata must match the actual executable protocol surface.
- Do not use commands like `deposit` as chain-specific funding shortcuts if the original protocol semantics define them as block transformations.

When a target chain cannot express the Solidity structure directly, adapt the implementation shape but keep the protocol shape. For example, Solidity separates the port-facing hook from the standard pipeline implementation and composes both explicitly on a host:

```solidity
abstract contract PipePayablePort is PortBase, PipeHook
contract ExampleHost is Pipeline, PipePayablePort
```

Most non-EVM chains do not have Solidity-style contract inheritance. A port can use Rust traits, modules, helper functions, account structs, or explicit composition instead. The important part is that the resulting host still has the same responsibilities and behavior as the EVM composition.

The tests are part of the blueprint. When porting a module, port the matching tests too:

| Source test | Porting target |
|-------------|----------------|
| `test/blocks.test.ts` | Cursor, writer, schema, and block-key compatibility. |
| `test/utils.test.ts` | ID layout, account/asset/node helpers, prefixes, and category checks. |
| `test/access.test.ts` | Commander, trusted node, guardian, and caller authorization behavior. |
| `test/commands.test.ts` | Standard command behavior and pipeline state threading. |
| `test/peer.test.ts` | Port entrypoints, port pipe payload handling, and trusted peer restrictions. |
| `test/validator.test.ts`, `test/ecdsa.test.ts` | Proof validation behavior, adapted to the destination chain's signature model. |
| query tests | Query surfaces and encoded response behavior where the port exposes equivalent queries. |

For wire-format work, the strongest compatibility test is cross-implementation round trip: build bytes with the TypeScript/Solidity helpers, parse them with the port, then build the same bytes in the port and parse them with the original tests. The byte output should match exactly.

---

## Three-Layer Port Model

Each non-EVM implementation has three layers.

These layers are an implementation strategy, not a redesign of the protocol. Keep the EVM protocol concepts recognizable, then translate only the parts that the destination chain cannot represent literally or efficiently, such as inheritance, ABI calls, `msg.sender`, `msg.value`, 20-byte addresses, storage layout, or dispatch mechanics.

### Layer 1 - Wire Format Library

A language-native implementation of `Decoders.sol` and `Writers.sol`. This is the most important deliverable because it makes every chain speak the same byte protocol.

```text
rootzero-protocol/ or sdk/rust/: cursor.rs, writer.rs, keys.rs
sdk/go/:   cursor.go, writer.go, keys.go
sdk/ts/:   cursor.ts, writer.ts, keys.ts
```

For Rust-based chains, this should start as a standalone `rootzero-protocol` library crate. CosmWasm, Solana, and NEAR adapters can all depend on it instead of each port reimplementing cursor/writer/key/schema/ID logic.

Each implementation exposes:

- `peek(buf, i) -> (key, payload_len)`
- `read_block(buf, i, expected_key) -> payload bytes`
- `write_block(key, payload) -> bytes`
- typed pack/unpack helpers for `Amount`, `Balance`, `Transaction`, `Step`, and `Context`

Block key constants are `keccak256("#name")[0:4]`.

### Layer 2 - Protocol Abstractions

These are equivalents of the Solidity abstract contracts, expressed in local primitives.

#### Access Control

State:

- `commander`: local commander host ID plus its resolved privileged native identity
- `nodes`: local trusted node IDs
- `guardians`: user account IDs assigned the guardian role

Checks:

- `is_trusted(caller)`: true if the caller is commander, self, or a trusted local node
- `enforce_commander(caller)`: admin-only operations

Examples:

| Chain | Access model |
|-------|--------------|
| Solana | Commander host ID resolved to a `Pubkey`; trusted nodes in account state; instruction-level checks. |
| CosmWasm | Commander host ID resolved to an `Addr`; `NODES: Map<LocalNodeId, bool>`; assertions in `execute()`. |
| NEAR | Commander host ID resolved to an `AccountId`; `nodes: UnorderedMap<LocalNodeId, bool>`; method preconditions. |

External configuration and authorization sets should use protocol IDs. Validate
and resolve the commander host ID once during initialization, then retain its
native signer/caller identity internally for comparisons that cannot be done
directly on protocol IDs.

#### Host Identity

On EVM:

```solidity
host = Nodes.toHost(address(this));
```

On other chains:

```text
host = local_ids.to_host(local_host_identity)
```

The host identity is stored in local program/contract state at initialization. It does not need to encode which chain it came from, because the runtime executing it is already the chain boundary.

#### Commands

Each command has:

- a deterministic local ID
- an announcement/registration record using the same logical event shape where the chain supports events
- input: `CommandContext { account, state, input }`
- output: the next Rootzero block stream state and a trusted native budget credit

The `input` and `state` are Rootzero block streams. Only state is threaded into
the next command; the pipeline adds the scalar command return to its shared
budget without checking it against forwarded value.

Every command implementation must account for its complete incoming state.
It must validate and consume the state, transform and return it, forward it
intact, or reject the invocation. Commands that accept no state must reject a
non-empty state stream. Ports must preserve this rule: silently ignoring state
or decoding only a prefix can destroy live balance, custody, or position value.

Chain-specific dispatch:

| Chain | Dispatch mechanism |
|-------|--------------------|
| EVM | ABI selector and `call()`. |
| Solana | Anchor instruction or CPI into a command program. |
| CosmWasm | `ExecuteMsg::Command { context }` or command-specific execute variant. |
| NEAR | Public method call with `CommandContext` arguments. |

#### Pipeline

The `pipe()` loop is pure protocol logic:

1. Iterate STEP blocks.
2. Decode `(cmd, value, input)` and deduct the plain `uint` native value directly
   from the scalar budget.
3. Give commands targeting the current host to its local execute hook first. A
   handled result uses the hook-authorized optimized internal output. An
   unhandled result is validated for trust before calling the command's normal
   entrypoint. Validate trust and call other local-chain command targets directly.
4. Thread the returned state bytes into the next step and add the returned native
   credit to the shared budget before executing the next step.
5. Require the final state to be empty.

The handoff flag and `relay { #bytes as input, #bytes as steps }` envelope let
the EVM pipeline transfer its untouched continuation to a flagged command.
Callers encode the command's ordinary input; the pipeline constructs the relay
envelope and stops executing the transferred steps locally.

The standard relay commands decode the envelope and call their transport hook
with four values: the account, command-specific `input`, a canonical destination
`#context`, and the command's funds. The context also contains the account,
complete forwarded state, and remaining STEP stream, so adapters can use the
account directly and forward the context without reconstructing protocol data.
A qualified `relay.input` schema describes the keyed block stream inside the
otherwise transport-defined input bytes. An adapter can use
`Blocks.exact` for exactly one block, or use the ordinary decoder and
close-validation pattern for a batch.

A local execute hook must return unhandled for a handoff ID so the normal
pipeline path can construct the continuation envelope. Handoff transfers the
remaining STEP bytes, not the source pipeline's complete native-value budget:
the command receives only its assigned STEP value, while returned credit and
the remaining source budget are settled normally on the source. The handoff
command must consume or forward its current state and return empty state because
no local continuation remains to consume returned state. Asynchronous transports
must not relinquish debt, position, or other state whose destination processing
may fail after the source has consumed it; the standard convention permits only
empty or balance state.

`pipe()` returns the remaining native-value budget to its caller. Per-command
native credit replenishes this budget, allowing one command to fund later
commands. The enclosing entrypoint settles the final budget once.

Pipeline execution should not extract a target chain ID. `execute` gets the
first opportunity to handle commands hosted by the current pipeline host and
must authorize any command it handles. Delegated and other command IDs are
authorized as trusted local nodes before using the local chain's call mechanism.

#### Port Pipe

`ports/Pipe.sol` is the cross-chain execution pattern to preserve. The port pipe entrypoint consumes raw CONTEXT blocks from a trusted local caller, then forwards the nested STEP stream into `pipe()`.

All contexts share one native-value budget. After the loop, `portPipePayable`
credits any nonzero remainder to the last context's account through `cashin`
and returns zero native credit. Context ordering determines the recipient.
Empty input with value passes the zero account to the host's `CashinHook`,
which owns account validation. A zero remainder skips the hook.
`Portal.forward` ignores successful return data; settlement belongs to the
pipeline port, so the portal does not decode the message to infer an account.

This means the bridge does not need a special "execute remote command" API. It only needs to deliver bytes to the destination host's port pipe. From that point onward, execution is identical to local pipeline execution.

#### Port Booking

`ports/Book.sol` implements `portBook` with portable bookkeeping logic:

1. Iterate a flat stream of paired ACCOUNT_AMOUNT blocks, debit then credit;
   publish `#input as (debit, credit)` in a `#groups` annotation on the port ID.
2. Decode both legs and call `BookHook.book` with their accounts, assets, and amounts.
3. The default implementation debits the source before crediting the destination, skipping zero amounts.
4. Let chain-specific hooks perform actual asset movement where needed.

For transfers, use the same asset and amount on both legs. Set an omitted leg's amount to zero for single-sided entries. The booking logic is portable because account and asset values are protocol IDs. Do not resolve account IDs just to update balances. Asset custody and transfer hooks are local, and those hooks may resolve IDs when native asset movement requires it.

### Layer 3 - Chain Adapters

Chain adapters implement the hooks that touch native assets and native call surfaces.

Everything above this layer should remain protocol-native. Adapters are where Rootzero protocol IDs become native pubkeys, account strings, contract addresses, denoms, token accounts, call messages, or attached-value operations.

```rust
trait AssetHooks {
    fn deposit(&mut self, account: [u8; 32], asset: [u8; 32], amount: u64) -> Result<()>;
    fn withdraw(&mut self, account: [u8; 32], asset: [u8; 32], amount: u64) -> Result<()>;
    fn payout(&mut self, account: [u8; 32], to: [u8; 32], asset: [u8; 32], amount: u64) -> Result<()>;
    fn settle_value(&mut self, account: [u8; 32], remaining: u64) -> Result<()>;
}
```

Examples:

| Chain | Hook implementation |
|-------|---------------------|
| Solana | Resolve Solana asset IDs to SPL mints/token accounts or native SOL, then perform CPI/system instructions. |
| CosmWasm | Resolve CosmWasm asset IDs to bank denoms, IBC denoms, or CW20 contract addresses, then emit the matching messages. |
| NEAR | Resolve NEAR asset IDs to native NEAR or NEP-141 account IDs, then perform the matching calls. |

---

## Concrete File Structure

### Solidity / EVM

No global non-EVM registry is needed. Keep the existing EVM-local helpers:

```text
contracts/utils/Nodes.sol       - EVM node IDs
contracts/utils/Assets.sol      - EVM asset IDs
contracts/utils/Accounts.sol    - EVM account IDs
contracts/utils/Ids.sol         - shared opaque/structured ID helpers
contracts/utils/Utils.sol       - EVM local base helpers
```

Optional additive helpers can be considered later, but avoid adding:

```text
contracts/registry/ChainIds.sol
toExternalBase(prefix, chainSlot)
```

Those would push foreign-chain knowledge into the EVM library.

### Rust SDK

```text
rootzero-protocol/
  Cargo.toml
  src/
    lib.rs
    blocks/
      cursor.rs
      writer.rs
      keys.rs
      schema.rs
    protocol/
      layout.rs
      ids.rs            - shared category/subtype helpers and ID traits, no chain registry
      accounts.rs
      assets.rs
      types.rs
      balances.rs       - BalanceStore trait
      pipeline.rs       - protocol-native pipeline traits/helpers where chain-neutral
    commands/
      base.rs
      debit.rs
      credit.rs
      deposit.rs
      withdraw.rs
      payout.rs
    ports/
      settle.rs

sdk/rust/
  Cargo.toml            - optional workspace/package wrapper around rootzero-protocol

sdk/rust/solana-host/
  src/
    lib.rs
    state.rs
    ids.rs              - Solana local ID construction and pubkey resolution
    dispatch.rs
    assets.rs           - Solana-native asset helpers, not ERC helpers
    bridge.rs          - destination bridge adapter; authenticates delivery, calls peer_pipe

sdk/rust/near-host/
  src/
    lib.rs
    state.rs
    ids.rs              - NEAR local ID construction and account ID resolution
    dispatch.rs
    assets.rs           - NEAR-native asset helpers, not ERC helpers
    bridge.rs
```

### CosmWasm SDK / Template

```text
sdk/cosmwasm/
  Cargo.toml            - depends on rootzero-protocol
  src/
    contract.rs
    state.rs
    ids.rs              - CosmWasm local ID construction and Addr resolution
    cursor.rs
    writer.rs
    pipeline.rs
    bridge.rs          - optional bridge adapter entrypoint
    commands.rs
    assets.rs           - CosmWasm-native asset helpers, not ERC helpers
```

CosmWasm contracts are normally Rust, so a Go SDK is only needed for off-chain Cosmos tooling. The core contract template should be Rust.

### TypeScript SDK

```text
sdk/ts/
  src/
    cursor.ts
    writer.ts
    keys.ts
    ids/
      evm.ts
      solana.ts
      cosmwasm.ts
      near.ts
    pipeline.ts
    pipe.ts             - builds CONTEXT payloads for local or bridged execution
    routes.ts           - bridge/orchestrator route table; never submitted as core ID data
```

The TypeScript SDK may know about many chains because it is off-chain orchestration code. That knowledge should not leak into the on-chain/runtime libraries.

---

## Key Interfaces

### Dispatcher

```rust
struct CommandOutput {
    state: Vec<u8>,
    credit: u128,
}

trait Dispatcher {
    fn dispatch(
        &mut self,
        target: LocalNodeId,
        account: [u8; 32],
        state: Vec<u8>,
        input: &[u8],
        value: u64,
    ) -> Result<CommandOutput>;
}
```

`LocalNodeId` can be a `u256` wrapper, but its interpretation belongs to the local chain module. If the native callable identity does not fit inside the ID, dispatch must resolve the ID before calling.

### PortPipe

```rust
trait PortPipe {
    type NativeValue;

    fn peer_pipe(
        &mut self,
        caller: LocalCaller,
        input: &[u8],
        value: Self::NativeValue,
    ) -> Result<Vec<u8>>;
}
```

The implementation enforces local peer authorization, parses CONTEXT blocks, and calls the same `pipe()` function used by local execution.

### LocalIds

```rust
trait LocalIds {
    type NativeIdentity;
    type DispatchTag;

    fn host(&self, identity: &Self::NativeIdentity) -> LocalNodeId;
    fn command(&self, tag: Self::DispatchTag, identity: &Self::NativeIdentity) -> LocalNodeId;
    fn peer(&self, tag: Self::DispatchTag, identity: &Self::NativeIdentity) -> LocalNodeId;
    fn opaque_hash(
        &self,
        category: u8,
        subtype: u8,
        identity: &Self::NativeIdentity,
    ) -> [u8; 29];
}
```

This is the replacement for a global chain registry. Each chain implements this trait using only native identity data.

### IdentityResolver

```rust
trait IdentityResolver {
    type NativeNodeIdentity;
    type NativeAccountIdentity;
    type NativeAssetIdentity;

    fn resolve_node(&self, id: LocalNodeId) -> Result<Self::NativeNodeIdentity>;
    fn resolve_account(&self, id: [u8; 32]) -> Result<Self::NativeAccountIdentity>;
    fn resolve_asset(&self, id: [u8; 32]) -> Result<Self::NativeAssetIdentity>;
}
```

For inline ID strategies, this can be a pure decoder. For lookup-backed
strategies, this reads local host state or verifies witness data. This is the
abstraction that replaces EVM's direct `address(uint160(id))` pattern on chains
whose identities do not fit in a structured payload.

Use this resolver sparingly. It is for native calls, native signer checks, native token transfers, and bridge adapter edges. It is not needed for ordinary balance keys or block-stream processing.

### BalanceStore

```rust
trait BalanceStore {
    fn credit(&mut self, account: [u8; 32], asset: [u8; 32], amount: u64) -> u64;
    fn debit(&mut self, account: [u8; 32], asset: [u8; 32], amount: u64) -> Result<u64>;
    fn balance(&self, account: [u8; 32], asset: [u8; 32]) -> u64;
}
```

Backed by Solana account data, CosmWasm storage, NEAR collections, or EVM mappings.

`BalanceStore` deliberately uses the protocol account ID as-is. It should not resolve `account` to a native address before reading or writing a balance.

---

## Implementation Sequence

1. **Rust wire format library**: port `Decoders.sol`, `Writers.sol`, and `Keys.sol`; validate with Solidity/TypeScript round trips.
2. **Shared Rust protocol crate**: package cursor, writer, keys, schema, shared ID taxonomy, protocol types, and storage/dispatch traits as `rootzero-protocol`.
3. **Identity strategy**: decide which node, account, and asset identities fit inline and which require local lookup.
4. **Local ID and resolver traits**: define `LocalIds` and `IdentityResolver` without any global chain registry.
5. **Protocol abstractions**: port access control, pipeline loop, command context, balance store, and peer posting.
6. **Port pipe port**: implement the local port pipe entrypoint that consumes CONTEXT blocks and calls `pipe()`.
7. **Standard command ports**: debit, credit, deposit, withdraw, payout, and the realization command family.
8. **CosmWasm host template**: wire `rootzero-protocol` to CosmWasm storage, `Addr` resolution, native denom/CW20/IBC assets, and bridge adapter entrypoints.
9. **Solana and NEAR templates**: repeat the same pattern with their native identity and asset hooks.
10. **TypeScript orchestrator SDK**: compose CONTEXT payloads for bridge delivery and keep route metadata outside the submitted bytes.

---

## Verification

| Test | What it checks |
|------|----------------|
| Wire format round trip | Build a STEP stream in TypeScript; parse it with Rust; verify identical `(cmd, value, input)`. |
| Local ID isolation | Solana ID constructors require only Solana program/account data and do not import EVM/Cosmos/NEAR constants. |
| ID resolution | For lookup-backed chains, construct an ID from a native identity, resolve it back from local state, and reject unknown IDs. |
| Balance opacity | Credit and debit balances using opaque account IDs without resolving them to native addresses. |
| Dispatch isolation | A host dispatches a local command ID without checking or parsing a foreign chain ID. |
| Lookup dispatch | A host dispatches a command whose native address does not fit in the ID by resolving the local node ID first. |
| Port pipe delivery | Feed bridge-delivered CONTEXT bytes into destination `port_pipe`; verify it calls the same pipeline path as local execution. |
| Command equivalence | Run `debitAccount` on EVM and a non-EVM host with equivalent `CommandContext` bytes; verify equivalent BALANCE output. |
| Pipeline execution | Run a two-step local pipeline, such as deposit then withdraw, and verify final state is empty. |
| Access control | Unauthorized local caller fails; trusted local node succeeds. |
| Bridge routing | TypeScript route table sends CONTEXT bytes to the intended host while keeping route metadata out of the submitted block bytes. |

Parity checklist:

1. Same block key derivation as original.
2. Same block payload layout and ordering.
3. Same command input/output block behavior.
4. Same peer/admin/guard accepted block schemas.
5. Same query response block bytes for equivalent state.
6. Chain-specific adapters are isolated from protocol wire logic.
7. Generic host registry dispatch works for all advertised commands, peers, queries, and guards.

---

## Main Change From The Previous Plan

The previous approach introduced explicit non-EVM chain slots, a `ChainIds.sol` registry, and `toExternalBase(prefix, chainSlot)`. That would make the libraries aware of other chains and would require ongoing coordination of global numeric identifiers.

This version removes that coupling. EVM keeps its EVM-local `block.chainid` behavior. New chain ports use local ID modules. Bridges carry raw CONTEXT bytes to a destination host, and each on-chain runtime only understands its own native identities, trusted nodes, assets, port pipe endpoint, and dispatch table.
