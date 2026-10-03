# CosmWasm Port Blueprint

This document is a starting point for creating a CosmWasm port of Rootzero in a blank Rust/CosmWasm project.

Use it together with:

- Project repository: `https://github.com/lastqubit/rootzero-contracts`
- Multi-chain port design: `docs/multi-chain-port.md`
- Local EVM behavior blueprint: `contracts/`, `test/`, and `test/helpers/blocks.ts`
- CosmWasm project/docs: `https://cosmwasm.com/` and `https://github.com/CosmWasm/cosmwasm`

The goal is not to make CosmWasm look like Solidity. The goal is to preserve Rootzero protocol behavior, wire bytes, ID taxonomy, command semantics, port pipe execution, access rules, and test outcomes while using native CosmWasm structure where that is clearer or more efficient.

## Core Rules

1. Stay protocol-native by default.
   Keep Rootzero IDs, block streams, balances, command contexts, and transaction records as protocol values. Convert to `Addr`, denom strings, CW20 contract addresses, or `CosmosMsg` only at adapter boundaries.

2. Use this repository as the blueprint.
   Port behavior from `https://github.com/lastqubit/rootzero-contracts`, not from memory. When a module is ported, port the matching tests.

3. Keep the shared prefix taxonomy.
   CosmWasm account IDs, node IDs, and asset IDs should still carry the shared `Account`, `Node`, and `Asset` category bits. Do not use EVM representation tags such as `Evm` for CosmWasm identities. Define CosmWasm representation tags.

   If an identity does not fit or should stay opaque, encode it as
   `[0x02][category][subtype][bytes29(hash)]`. Resolve the full native identity
   through local lookup or witness data only at adapter boundaries. Opaque
   preimages use `[formatHash][category][subtype][payload...]`; `0x01` means
   keccak256. The remaining payload format is intentionally left for a future
   convention.

4. No global chain IDs.
   CosmWasm code should not know about EVM chain IDs, Solana IDs, or a global chain registry. Bridge routes are transport metadata outside Rootzero core.

5. Use native CosmWasm asset helpers.
   Do not port `toErc20` or `erc20` literally. Create helpers such as
   `to_native_denom`, `to_cw20`, and `to_ibc_denom`.

6. Mirror protocol structure, not inefficient mechanics.
   Solidity inheritance becomes Rust modules, traits, helper functions, and explicit composition. Keep the responsibilities recognizable.

## Recommended Empty Project Layout

Start with a Rust workspace. Build the shared protocol crate first, then make the CosmWasm contract depend on it.

```text
rootzero-cosmwasm-workspace/
  Cargo.toml
  crates/
    rootzero-protocol/
      Cargo.toml
      src/
        lib.rs
        blocks/
          mod.rs
          keys.rs
          schema.rs
          cursor.rs
          writer.rs
        protocol/
          mod.rs
          types.rs
          layout.rs
          ids.rs
          accounts.rs
          assets.rs
          balances.rs
          pipeline.rs
        commands/
          mod.rs
          base.rs
          debit.rs
          credit.rs
        ports/
          mod.rs
          settle.rs
      tests/
        blocks.rs
        ids.rs

    rootzero-cosmwasm/
      Cargo.toml
      src/
        lib.rs
        contract.rs
        error.rs
        msg.rs
        state.rs
        access.rs
        pipeline.rs
        commands/
          mod.rs
          deposit.rs
          withdraw.rs
          payout.rs
        ports/
          mod.rs
          pipe.rs
        adapter/
          mod.rs
          assets.rs
          bridge.rs
          resolver.rs
      tests/
        access.rs
        commands.rs
        peer_pipe.rs
```

Suggested dependency categories:

- `rootzero-protocol` should depend only on normal Rust crates needed for protocol logic, such as a Keccak implementation and possibly `thiserror`. It should not depend on `cosmwasm-std`.
- `cosmwasm-std` for `Deps`, `DepsMut`, `Env`, `MessageInfo`, `Response`, `Binary`, `CosmosMsg`, `BankMsg`, and contract entrypoints.
- `cw-storage-plus` for `Item` and `Map`.
- `cosmwasm-schema` and `schemars` for message/schema generation.
- `serde` for message serialization.
- `thiserror` for contract errors.
- a Keccak implementation such as `sha3` or `tiny-keccak` for Rootzero block keys and fingerprints. Use Keccak-256, not SHA3-256.

Use current versions from the CosmWasm docs when creating the project.

## Message Surface

Keep the external CosmWasm message surface small. Most Rootzero logic should operate on raw protocol bytes.

```rust
pub enum InstantiateMsg {
    Init {
        commander: Binary,
    },
}

pub enum ExecuteMsg {
    PortPipe {
        input: Binary,
    },
    BridgeReceive {
        source: BridgeSource,
        payload: Binary,
    },
    SetTrustedNode {
        node: Binary,
        trusted: bool,
    },
    SetGuardian {
        account: Binary,
        trusted: bool,
    },
}

pub enum QueryMsg {
    Balance {
        account: Binary,
        asset: Binary,
    },
    TrustedNode {
        node: Binary,
    },
}
```

`PortPipe { input }` is the CosmWasm equivalent of the EVM port pipe entrypoint. It receives raw CONTEXT block bytes and runs the local pipeline.

`BridgeReceive` is optional. Use it if a bridge must call a specific adapter entrypoint first. The bridge adapter should authenticate the bridge message, then call the same internal `peer_pipe` implementation.

## Storage

Use protocol IDs as storage keys whenever possible.

```text
CONFIG:
  commander_id: [u8; 32]
  commander: Addr // resolved internal identity
  host_id: [u8; 32]

TRUSTED_NODES:
  LocalNodeId bytes -> bool

GUARDIANS:
  User AccountId bytes -> bool

BALANCES:
  (account_id bytes, asset_id bytes) -> Uint128

NODE_RESOLVER:
  node_id bytes -> Addr

ACCOUNT_RESOLVER:
  account_id bytes -> Addr

ASSET_RESOLVER:
  asset_id bytes -> NativeAsset
```

Important: `BALANCES` must use the protocol account ID as-is. Do not resolve account IDs to `Addr` before reading or writing balances.

Resolution is only for native boundaries:

- dispatching to a local contract address
- checking a native caller when the protocol ID alone is not enough
- sending bank tokens
- executing a CW20 transfer
- bridge adapter checks

## Shared Rust Protocol Crate

Build `crates/rootzero-protocol` before the CosmWasm contract. This crate should be usable by any Rust-based port, including CosmWasm, Solana, and NEAR.

It owns:

- block keys
- cursor parsing
- writer encoding
- schema constants
- shared ID prefix/category helpers
- protocol types such as `CommandContext`, `Tx`, and `AssetAmount`
- balance store traits
- dispatcher/pipeline traits where chain-neutral
- pure command logic where it does not touch native chain APIs

It must not own:

- CosmWasm `Addr`
- CosmWasm `Deps` / `DepsMut`
- `BankMsg`, `WasmMsg`, or `CosmosMsg`
- chain storage details
- bridge authentication
- native asset transfer logic

This crate is the first milestone. The first success condition is that its block tests pass against fixtures from `test/helpers/blocks.ts`.

## Wire Format

The wire format must match the Solidity implementation exactly.

```text
[bytes4 key][uint32 payload_len][payload]
```

Rules:

- `key = keccak256("#name")[0:4]`
- `payload_len` is a 4-byte big-endian `uint32`
- all fixed words are 32 bytes, big-endian for integers
- nested bytes are encoded as `#bytes` blocks
- STEP payload is `[cmd:32][value:32][#input]`
- CONTEXT payload is `[account:32][#state][#input]`

Port these first:

```text
crates/rootzero-protocol/src/blocks/keys.rs
crates/rootzero-protocol/src/blocks/cursor.rs
crates/rootzero-protocol/src/blocks/writer.rs
crates/rootzero-protocol/src/blocks/schema.rs
```

Then port `test/blocks.test.ts` into Rust tests. The first success condition is byte-for-byte compatibility with `test/helpers/blocks.ts`.

## ID Taxonomy

Create CosmWasm-native representation tags for structured IDs, but keep shared
Rootzero categories and subtypes.

Example:

```text
[CosmWasm][Account][User][local handle payload]
[CosmWasm][Node][Command][local field][message tag][contract handle]
[CosmWasm][Asset][NativeDenom][local handle payload]
[CosmWasm][Asset][Cw20][local handle payload]
[CosmWasm][Asset][IbcDenom][local handle payload]
[0x02][category][subtype][bytes29(hash(canonical_preimage))]
```

Category checks remain protocol-wide for both structured and opaque IDs:

```rust
fn is_account(id: &[u8; 32]) -> bool {
    id[1] == CATEGORY_ACCOUNT
}

fn is_asset(id: &[u8; 32]) -> bool {
    id[1] == CATEGORY_ASSET
}
```

Opaque IDs carry category and subtype in their second and third bytes. Do not
create CosmWasm accounts that fail a shared `is_account` check, or CosmWasm
assets that fail `is_asset`.

Reserve the shared asset subtype assignments `Derived = 0x01`,
`Virtual = 0x02`, and `Erc20 = 0x03`. Derived and Virtual have no dedicated
helpers or standardized subtype-specific payloads. A CosmWasm port should not
expose ERC-20 helpers.
Chain-specific asset subtypes must not reuse these assigned values.

## CosmWasm Asset Helpers

Port the helper pattern, not ERC helper names.

Create helpers like:

```rust
fn to_native_denom(denom: &str) -> AssetId;
fn to_cw20(contract: &Addr) -> AssetId;
fn to_ibc_denom(denom: &str) -> AssetId;
fn is_native_denom(asset: &AssetId) -> bool;
fn is_cw20(asset: &AssetId) -> bool;
fn is_ibc_denom(asset: &AssetId) -> bool;
```

Suggested native asset representation:

```rust
pub enum NativeAsset {
    NativeDenom { denom: String },
    Cw20 { contract: Addr },
    IbcDenom { denom: String },
}
```

Balances are keyed by the asset ID itself. When a native asset has long
metadata, use an opaque asset ID and resolve the metadata by lookup or witness
only when native movement requires it.

## Access Control

Port the behavior of `core/Access.sol`.

Access control belongs in the CosmWasm contract crate because it depends on `MessageInfo.sender`, `Addr`, and storage. Reuse protocol IDs and traits from `rootzero-protocol`, but keep CosmWasm caller handling in `rootzero-cosmwasm`.

State:

```text
commander_id: LocalHostId
commander: Addr // resolved internal identity
trusted nodes: LocalNodeId -> bool
guardians: User AccountId -> bool
```

Rules:

- commander can perform admin operations
- trusted local nodes can call peer/command surfaces where required
- direct commander calls to peer entrypoints should follow the EVM behavior if the port exposes equivalent peer restrictions
- store trusted nodes as protocol node IDs, not as raw `Addr` unless a native comparison requires a resolver

Instantiation accepts the protocol commander host ID, validates and resolves it
once, and retains the native `Addr` only for runtime caller checks. CosmWasm
comparison usually starts from `MessageInfo.sender`. If the caller is a bridge
contract or trusted peer contract, resolve or derive its local node ID and
compare against `TRUSTED_NODES`.

## Pipeline

Port the pure pipeline loop:

```rust
fn pipe(
    deps: DepsMut,
    account: AccountId,
    state: Vec<u8>,
    steps: &[u8],
    mut budget: NativeBudget,
) -> Result<NativeBudget, ContractError> {
    // iterate STEP blocks
    // dispatch each local command and receive (state, credit)
    // thread returned state into the next step
    // add the trusted native credit to the shared budget before the next step
    // require final state is empty
    // return the remaining native budget
}
```

`pipe` returns the remaining native budget to the entrypoint. Each command also
returns an unchecked native credit that replenishes the shared budget, allowing
later commands to spend it. This credit is trusted command output and is not
constrained by the value forwarded to the command. The entrypoint settles the
final budget once.

Do not parse a target chain ID from a STEP command. The command is already local to this CosmWasm host.

Put chain-neutral STEP parsing and dispatcher traits in `rootzero-protocol`. Put CosmWasm-specific dispatch, storage, and message generation in `rootzero-cosmwasm`.

Dispatch can be implemented as an internal table:

```rust
match command_tag(cmd)? {
    TAG_DEBIT => commands::debit::execute(...),
    TAG_CREDIT => commands::credit::execute(...),
    TAG_DEPOSIT => commands::deposit::execute(...),
    TAG_WITHDRAW => commands::withdraw::execute(...),
    TAG_PAYOUT => commands::payout::execute(...),
    _ => Err(ContractError::UnknownCommand {}),
}
```

If a command target refers to another local contract, resolve the node ID to `Addr` and emit a `WasmMsg::Execute`. If a native-efficient internal dispatch is enough, prefer internal dispatch.

## Port Pipe

Port `ports/Pipe.sol` as the cross-chain byte execution surface.

External CosmWasm entrypoint:

```rust
ExecuteMsg::PortPipe { input }
```

Internal behavior:

1. Enforce trusted peer/bridge caller.
2. Parse `input` as one or more CONTEXT blocks.
3. For each CONTEXT block, unpack `(account, state, input)`.
4. Thread the remaining budget through `budget = pipe(account, state, input, budget)`.
5. Return an empty response payload unless the EVM behavior being ported returns data.

The bridge should deliver raw CONTEXT bytes. The bridge route, source chain, source sender, nonce, and proof are bridge adapter data, not Rootzero core data.

## Commands

Port commands by behavior:

```text
debitAccount
creditAccount
deposit
withdraw
payout
realize
```

Command inputs and state outputs remain Rootzero block streams. Every command
returns `state` for the next pipeline step and a trusted scalar native `credit`
for the shared execution budget.

Treat incoming state as a linear value. Each command must validate and consume
the complete state stream, transform and return it, forward it intact, or
reject it. A command that declares no state must reject non-empty state; it must
never silently discard balance, custody, or position blocks.

`CommandContext`:

```rust
pub struct CommandContext {
    pub account: [u8; 32],
    pub state: Vec<u8>,
    pub input: Vec<u8>,
}

pub struct CommandOutput {
    pub state: Vec<u8>,
    pub credit: Uint128,
}
```

`debit` and `credit` should use protocol IDs directly:

```text
balance key = (account_id, asset_id)
```

`deposit`, `withdraw`, `payout`, and the realization commands may cross into adapter logic because native tokens need bank/CW20 messages or value conversion.

As a rule of thumb:

- `debit` and `credit` can mostly live in `rootzero-protocol` because they are ledger operations over protocol IDs.
- `deposit`, `withdraw`, `payout`, and the realization commands should have protocol-level input parsing in `rootzero-protocol`, but native asset movement or conversion in `rootzero-cosmwasm`.

## Native Asset Adapter

The adapter is where protocol IDs become Cosmos/CosmWasm messages.

Examples:

```rust
fn deposit(
    deps: DepsMut,
    info: &MessageInfo,
    account: AccountId,
    asset: AssetId,
    amount: Uint128,
) -> Result<Vec<CosmosMsg>, ContractError>;

fn withdraw(
    deps: DepsMut,
    account: AccountId,
    asset: AssetId,
    amount: Uint128,
) -> Result<Vec<CosmosMsg>, ContractError>;
```

Native denom deposit:

- inspect `info.funds`
- verify the expected denom and amount were attached
- credit the protocol balance to `account`

CW20 deposit:

- use a CW20 receive flow or a trusted adapter flow
- verify the sender/token contract
- credit the protocol balance to `account`

Withdraw/payout:

- debit protocol balance first
- resolve asset ID to `NativeAsset`
- emit `BankMsg::Send` for native denoms
- emit `WasmMsg::Execute` for CW20 transfers

## Events

CosmWasm does not emit Solidity events, but `Response::add_attribute` and custom events can preserve the important indexing data.

Mirror event meaning, not ABI mechanics.

Suggested event names:

```text
rootzero.introduction
rootzero.command
rootzero.peer
rootzero.balance
rootzero.pipeline
rootzero.bridge_receive
```

Include protocol IDs as hex strings and native addresses only when the event is describing adapter behavior.

## Tests To Port First

Port tests from `https://github.com/lastqubit/rootzero-contracts` in this order:

1. `test/blocks.test.ts`
   Validate keys, headers, cursor movement, grouped runs, nested `#bytes`, STEP, CONTEXT, BALANCE, ASSET_AMOUNT, and TRANSACTION.

2. `test/utils.test.ts`
   Validate shared category checks, CosmWasm representation tags, local ID construction, asset helpers, opaque hash IDs, and resolver behavior.

3. `test/access.test.ts`
   Validate commander, trusted node, guardian, and peer restrictions.

4. `test/commands.test.ts`
   Validate debit, credit, deposit, withdraw, payout, and pipeline state threading.

5. `test/peer.test.ts`
   Validate port pipe byte delivery, batching, trusted caller checks, and final empty state.

6. Query tests as needed.
   Port query behavior only for query surfaces the CosmWasm host exposes.

For every block writer test, use cross-implementation fixtures:

```text
TypeScript helper bytes -> CosmWasm parser -> expected fields
CosmWasm writer bytes -> TypeScript/Solidity parser -> exact byte match
```

## Implementation Order

1. Create the Rust workspace with `crates/rootzero-protocol` and `crates/rootzero-cosmwasm`.
2. Build `rootzero-protocol` block keys, cursor, writer, schema, and tests.
3. Add `rootzero-protocol` layout, ID category helpers, account helpers, asset traits, protocol types, and balance traits.
4. Add `rootzero-protocol` command context and pure ledger command helpers.
5. Make `rootzero-cosmwasm` depend on `rootzero-protocol`.
6. Add CosmWasm storage and resolver maps.
7. Add CosmWasm access control.
8. Add CosmWasm pipeline dispatch.
9. Add CosmWasm port pipe.
10. Add CosmWasm native asset adapter.
11. Add bridge adapter if needed.
12. Port test suites until behavior matches the EVM blueprint.

## Acceptance Checklist

- `#block` bytes are identical to the EVM/TypeScript helpers.
- `rootzero-protocol` has no dependency on `cosmwasm-std`.
- CosmWasm imports protocol parsing, writing, keys, schema, and ID helpers from `rootzero-protocol`.
- `is_account`, `is_asset`, and node category checks work for CosmWasm IDs.
- No EVM representation tags are used for CosmWasm identities.
- No ERC helper names are used unless wrapping real EVM/ERC assets.
- Account balances use protocol account IDs as keys.
- Asset/account/node resolution happens only at native boundaries.
- `PortPipe` accepts raw CONTEXT bytes and calls the same pipeline path as local execution.
- STEP commands are local CosmWasm command IDs.
- The port has no global chain ID registry.
- Ported tests pass against fixtures from `rootzero-contracts`.
