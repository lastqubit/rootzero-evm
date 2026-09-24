# rootzero

rootzero is a protocol for building **hosts**: contracts that expose a uniform
set of endpoints over accounts and assets — commands that change state,
queries that read it, and port links that connect hosts to each other, on the
same chain or across chains.

This repository is `@rootzero/contracts`, the Solidity library for the EVM port
of the protocol: the base contracts, block codecs, and helpers that rootzero
applications compose.

Two decisions shape everything below. First, all data that crosses a host
boundary is encoded in one binary block format, so a input means the same
bytes on every chain. Second, every surface operates on *runs* of blocks rather
than single values, so batching is the default, not a feature added later. This
guide introduces the protocol bottom-up: blocks, then identities, then hosts
and the endpoints built on top of them.

## Quick Start

Scaffold a ready-to-run Hardhat project, or add the library to an existing
one:

```bash
npx create-rootzero@latest my-app
# or
npm install @rootzero/contracts
```

A minimal commander-only host composes `CommandHost` with the endpoints it
needs and implements their policy hooks:

```solidity
// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { Balances, CommandHost } from "@rootzero/contracts/Core.sol";
import { Deposit } from "@rootzero/contracts/Endpoints.sol";

contract ExampleHost is CommandHost, Balances, Deposit {
    constructor(uint commander) CommandHost(commander) {}

    function deposit(bytes32 account, bytes32 asset, uint amount) internal override returns (uint) {
        uint balance = creditTo(account, asset, amount);
        emit Balance(account, asset, balance, int(amount));
        return amount;
    }
}
```

`CommandHost` requires a nonzero local commander host ID and accepts command
calls only from its embedded native caller. It has no built-in admin commands, peer registry, guardians,
inbound introduction endpoint, generic execution command, or native-token
receive function. Use `Host` instead when the application needs those advanced
facilities; its commands accept the commander, the host itself, and explicitly
authorized host callers.

Both host types introduce themselves during deployment when the native target
encoded by the commander host ID is a contract. That commander must implement
`introduce(uint,uint)` and accept the call, otherwise deployment reverts. Host
IDs encoding EOAs do not receive an introduction call.

Host contracts are designed for fresh deployment rather than proxy upgrades.
Releases may change inheritance storage layout, immutable configuration, and
encoded identity formats; storage compatibility across versions is not
supported.

Pipelines and trusted outbound port callers require `CommandAccess` and
`PortAccess` implementations respectively. The advanced `Host` supplies both
directly through its node policy, while `CommandHost` deliberately does not. A
minimal host can implement narrow custom policies. Both access capabilities
return the authorized endpoint's selector and address for direct use with the
free raw-call helpers.

Deploy it with the local host ID encoding your native identity as commander and you can call its commands
directly. A input is a run of binary blocks — here, a single `#amount` block
asking to deposit an asset (the encoders are a few lines each; see
[`test/helpers/setup.ts`](test/helpers/setup.ts) and
[`test/helpers/blocks.ts`](test/helpers/blocks.ts) for reference
implementations):

```ts
const commander = await hostId(deployer.address);
const host = await ethers.deployContract("ExampleHost", [commander]);

const account = encodeUserAccount(user.address); // receiving account
const input = encodeAmountBlock(asset, 100n); // what to deposit
await host.deposit({ account, state: "0x", input: input }); // emits Balance
```

The rest of this guide explains the ideas this example leans on — blocks, IDs,
hosts, commands — and the surfaces built on top of them.

## Blocks

Every input, response, and piece of in-flight state is a stream of typed
blocks. A block is a four-byte key, a four-byte big-endian length, and a
payload:

```txt
[bytes4 key][uint32 payloadLen][payload]
```

The key is usually `bytes4(keccak256("#name"))`, and the payload layout is
described by a schema body published under an alias. For example, the standard
`amount` block that requests a deposit:

```txt
amount: { bytes32 asset, uint amount }
```

is 72 bytes on the wire: an 8-byte header followed by two big-endian 32-byte
fields. There is no ABI encoding and no chain-specific type anywhere in the
format — field types are chain-neutral integers, bytes, and booleans. A deposit
input built for an EVM host is byte-for-byte the input a CosmWasm or Solana
port would parse; what differs per chain is how a host *resolves* the
identifiers inside, never how the bytes are laid out.

Schemas can express more than flat fields: a block may contain any number of
nested child blocks (`#bytes as payload` names raw dynamic bytes), items can be
marked `maybe` when their empty form is accepted or `many` when they form a
list, and aliases and dotted field paths give off-chain tooling presentation
names without changing a single byte on the wire. Declared child headers are
always present; a zero payload length represents an empty block. An `at N` hint
can reposition one field in off-chain presentation without changing its wire
position. Qualified schema names such as `relay.input` describe encoded block
streams inside aliased `#bytes` fields, preserving ordinary block headers and
decoder helpers; schemas emitted locally by the active host take precedence
over trusted-context and standard schemas with the same name.
Schema strings may start with an optional `name:` prefix. For example,
`assets: many #asset as assets` names the schema `assets` and independently
names its list item `assets`; helpers take the complete string without a
separate name argument.
Standard block aliases are intrinsic protocol metadata: indexers resolve names
such as `balance`, `step`, and `context` from their standard keys even when no
named schema annotation is emitted.

Entities such as commands and assets may carry a `#counterparty { bytes32 account }`
annotation identifying their counterparty account, including host accounts. The latest trusted value
replaces the earlier association, and account zero identifies Rootzero. The
helper emits the claim without validating either ID or granting authority.
The full schema language is specified in
[`docs/Schema.md`](https://github.com/lastqubit/rootzero-evm/blob/main/docs/Schema.md). The standard block schemas live in
`Schemas` and their runtime keys in `Keys` (both via
`@rootzero/contracts/Codec.sol`).

A rare top-level list is published as a custom schema consisting of one item,
such as `many #asset` or `{ many #asset }`. Its context-local schema key becomes
the outer block key accepted by the endpoint; a list alongside sibling items
continues to use the generic `#list` key.

## Batches

An input is not a single struct; it is a run of blocks. One `#amount` block
asks for one deposit, five blocks ask for five, and the code path is identical
— every endpoint parses with a cursor and loops until the stream is exhausted.
The descriptor lane key is the prime item: it is the block type that may repeat
for batching. Each top-level block represents one operation; fixed compositions
use a custom parent block.

Off-chain, building a batch is concatenation. Using the reference encoders from
[`test/helpers/blocks.ts`](test/helpers/blocks.ts):

```ts
import { concat } from "ethers";
import { encodeAmountBlock } from "./helpers/blocks";

const input = concat([
  encodeAmountBlock(usdc, 250_000_000n),
  encodeAmountBlock(dai, 250n * 10n ** 18n),
]);
// deposit(input) returns two #balance blocks and zero native budget credit
```

Everything downstream keeps this shape: commands loop over input blocks,
posting ports loop over transactions, and pipelines loop over steps. Batching
is never a special case.

## IDs, Accounts, Assets, and Nodes

Everything the protocol touches - accounts, assets, chains, hosts, endpoints -
is identified by one 32-byte word. The first byte selects the convention:

- `0x00`: null/unset ID.
- `0x01`: Rootzero-native structured ID.
- `0x02`: opaque ID, encoded as
  `0x02 || category || subtype || bytes29(hash)`. The hash preimage is
  not recoverable from the ID; use a lookup table or witness data when the
  native account, asset metadata, or node target is needed.
- `0x03`: EVM structured ID. The value can be deconstructed according to its
  EVM layout.

Opaque preimages start with:

```txt
[uint8 formatHash][uint8 category][uint8 subtype][payload...]
```

`0x01` means keccak256. The category and subtype are copied into the ID and
included in the hash, binding its visible type to the opaque identity. The
remaining payload format is host/domain-specific until a future standard
defines it.

Opaque and structured IDs share the same category and subtype taxonomy. This
allows generic validation of an opaque account, asset, or node without exposing
or resolving its native identity. The Solidity helpers below construct and
deconstruct IDs.

Structured EVM IDs use:

```txt
[uint32 type][uint32 chainid][192-bit payload]
```

Embedded EVM addresses always occupy the low 160 bits:

```txt
Account / ERC-20: [type:4][chain:4][zero:4]    [address:20]
Node:            [type:4][chain:4][selector:4][address:20]
```

Account and ERC-20 encoders leave the middle four bytes zero. After validating
the ID's representation and category, extract the address with
`address(uint160(uint256(id)))`.

where `type` packs
`[uint8 representation][uint8 category][uint8 subtype][uint8 flags]`. A
structured ID announces what it is (an account, an asset, a node) and which
chain it lives on, and the payload usually embeds the underlying address. User
accounts are chain-agnostic, while admin accounts are chain-local. Guardians
are normal user accounts assigned a host-specific role.
Assets are unique IDs in the same single-word form as accounts and nodes.
Nodes are hosts, commands, ports, queries, and guards.

Asset subtype `0x00` identifies the default asset for representations that
define one. `Derived = 0x01` and `Virtual = 0x02` remain reserved taxonomy
values without dedicated helpers or a standardized payload. `Erc20 = 0x03`
identifies an ERC-20 asset.

The Rootzero asset is the singleton global ID
`[Rootzero][Asset][0][0]` with zero chain and payload fields. Its exact value is
`0x0103000000000000000000000000000000000000000000000000000000000000`
on every chain. Access it as `Assets.Rootzero`; EVM chain-coin
and ERC-20 asset IDs remain chain-local.

Opaque asset declarations use `AssetPreimage(bytes32 indexed asset, bytes preimage)`.
The asset ID is indexed and there is no host argument. The preimage uses
`[0x01][Asset][subtype][payload...]`, letting offchain indexers or witnesses
verify and resolve
`[0x02][Asset][subtype][bytes29(keccak256(preimage))]` assets.

The `Utils.sol` entry point provides the constructors and inspectors:

```solidity
bytes32 account = Accounts.toUser(msg.sender); // chain-agnostic user account
bytes32 asset = Assets.toErc20(tokenAddress);  // ERC-20 asset ID
uint hostId = Nodes.toHost(address(this));       // host node ID
bytes32 hostAccount = Accounts.toHost(hostId); // deterministic host account
bytes32 opaque = Ids.toKeccak(preimage);  // preimage: 0x01 || category || subtype || payload
```

Host accounts use `[Evm][Account][Host][0]`, a chain ID, and an address in
bits `[159:0]`. `Layout.Host` is shared with host nodes; the category distinguishes
them. `Accounts.toHost(address)` uses the current chain, while `Accounts.toHost(uint)`
validates a host node prefix and preserves its chain and address, including remote
chains. `Accounts.isHost` classifies the prefix; `Accounts.host` additionally
requires a nonzero address. Neither grants authority or requires deployed code.
A host account can be used with `settle`; the same host account can also identify a position handled by `realize`.

## Hosts

A host is one contract assembled from mixins. The base `Host` brings access
control and the admin surface (authorize, unauthorize, appoint, dismiss,
annotate, executePayable) plus the guardian `revoke` action; you add the
endpoints you need and the policy hooks they require. Keeping a ledger is
optional: the `Balances` mixin provides an account-and-asset ledger; hosts store their
own balances under `Accounts.toHost(host)`, but a host can just as well
implement commands that hold no persistent state in the host at all —
forwarding funds elsewhere, or operating only on the state threaded through a
pipeline.

Access capabilities used by commands, ports, pipelines, and guards are abstract
hooks. The two host bases provide the concrete policies: `CommandHost` accepts
commands only from its commander, while `Host` directly implements commander,
admin, node, peer, port, command, and guardian access. Guardian state and
enforcement are part of `Host`; there is no separate guardian policy contract.
Hosts that implement the allowance hook can additionally inherit the opt-in
`RevokeAllowance` guard, which accepts `hostAsset { uint host, bytes32 asset }`
entries and always applies a zero allowance.

Trust is explicit and minimal. Each host receives an immutable **commander host
ID** at construction. The EVM port validates that it is local, extracts its
native address internally for caller checks, and derives the **admin account**
from that native identity.
Other contracts become callers only when their node ID is authorized into the
host's trusted set, and **guardians** are accounts allowed to take protective
actions. At deployment, a host introduces itself to its commander, which is how
host topology becomes discoverable.

The `ExampleHost` in the quick start shows the resulting split, and it runs
through the whole library: mixins implement the protocol mechanics (parsing,
batching, discovery events), and small virtual hooks let the host decide
policy — where funds come from, how the ledger is keyed, what gets emitted.

## Commands

Commands are the write endpoints. Every command receives the same context:

```solidity
struct CommandContext {
    bytes32 account; // acting account
    bytes state;     // block stream produced by the previous command
    bytes input;     // block stream for this invocation
}
```

Every command returns a `state` block stream and a trusted native `credit`.
State is threaded into the next pipeline step, while credit replenishes the
shared pipeline budget without validation against forwarded call value.
Command trust is the authority boundary.

State is linear, not optional ambient context. A command is responsible for
the entire state stream it receives: it must validate and consume it, transform
and return it, forward it intact, or revert. A command must never succeed while
silently ignoring or dropping supplied state. Descriptor schemas remain
discovery metadata; the command's decoding and loop implementation defines its
runtime source semantics. A command that does not consume supplied state rejects
it when closing, while `takeRawState` explicitly consumes an intact forwarded
state source. `takeRawBalances` additionally validates every forwarded block as
BALANCE and is used by `relayBalancePayable`; empty state remains accepted.
This is especially important for `#position`, because dropping it could
silently discard an outstanding debt requirement.

The input carries instructions; the state carries live value. While a sequence
of commands executes, `#balance`, `#custody`, and `#position` blocks in
the state are the value being moved — produced by one command, consumed by the
next. Balance carries `{ asset, amount }`,
custody carries `{ host, asset, amount }`, and position carries the flat
position `{ asset, amount, liability, debt, counterparty }`. The counterparty
field identifies the settlement counterparty. Zero identifies Rootzero and
is handled by exact booking through `Settlement.settle`. Generic codecs preserve the field;
`settle` passes all five fields as a `Position memory` struct to its hook for
counterparty validation and authorization. Settlement hooks take
`(account, position)`, plus `Execution memory funds` for funded settlement.
Settlement accepts empty input and consumes any number of POSITION blocks.
Producers enforce minimum asset amounts and maximum debts before emitting their
final positions, using packed LIMITS where appropriate. Producers handle fees
before supplying the position: `amount` is the final net receipt and `debt` is the final total payment.
`Settlement` receives the final position, books zero-counterparty positions on the active
account, and passes nonzero counterparties to the account hooks when exchanging the
exact debt and asset quantities. It adds no fees and makes no separate host
fee credits. Account validation and authorization belong to the host's debit/credit
hooks, or its custom `BookHook` if it bypasses them. Empty exchanges skip the
account hooks, so they do not validate the counterparty.

`Repay` settles only the debt: `POSITION → POSITION` with empty input. Its
`RepayHook.repay(account, position)` must satisfy the entire debt or revert,
without mutating the position. The command then sets `debt = 0` and preserves
all other fields. `Settlement.repay` uses `BookHook` to debit the account and,
for a nonzero counterparty, credit that counterparty with the exact payment.
Zero debt skips booking. A following `Settle` consumes the remaining asset leg.

Every nonzero position counterparty is an account, including host accounts.
`settle` can exchange balances with any account counterparty on the executing
host. A host account can instead be realized by its host, whose hook compares
against `Accounts.toHost(host)` and fulfills the obligation before returning zero.
The subtype identifies the account, not the route: offchain metadata and available
balances determine where to settle or realize. See [counterparty semantics](docs/Schema.md#counterparty-semantics).

Hosts that maintain account balances implement `settle`; hosts without their own
balance ledger implement `realize`. A production host chooses one model rather
than exposing both for the same operation. `Settlement` supplies reusable ledger
mechanics with a default `settle` implementation that applies final quantities exactly.

Either side of a position may be absent. An absent asset side is encoded as
`asset = 0, amount = 0`; an absent liability side is encoded as
`liability = 0, debt = 0`. This mirrors transaction blocks, where a zero `from`
or `to` omits that side of the transfer. A one-sided position remains useful
when a command must preserve position-shaped state for later composition;
a liability-only position is the standard representation of debt. An asset-only
value can also use the narrower `#balance` block.

`#position` is general live state rather than a persisted
lending-specific debt record. Its liability side carries value owed or required; it
pairs that liability with value acquired or controlled. A command may preserve
or replace either side and return the resulting state for the next step;
`settle` terminally consumes the position, exchanging with an account
counterparty or applying a zero-counterparty booking. An optional `checkPosition`
step validates limits before settlement. This supports swaps,
borrowing, refinancing, collateral changes, callback obligations, cross-host
claims, fees, netting, and other multi-step operations. Positions are
transient representations and do not themselves create or erase an obligation
recorded by an external system.

At settlement, the debt side is the final total payment and the asset side is
the final net receipt, with producer fees already accounted for. Limits protect
these quantities; they do not cover separate charges outside the position.

The quantity in a debt side is an exact obligation. A command that consumes
`debt = 100` must deliver, make available, or otherwise satisfy all `100`, or
revert. Transfer fees and other sourcing costs are paid in addition to the debt
or reflected in the gross amount sourced upstream; they must not silently
reduce the fulfilled quantity. When fulfillment produces custody, the amount
that actually reaches custody must equal the debt. Partial fulfillment requires
preserving the unsatisfied remainder in a position rather than consuming it.

The standard `Deposit` mixin shows the canonical shape: open the execution,
decode its input, call the hook, and write the output run. Execution helpers
route known state blocks (`#balance`, `#custody`, and `#position`) to
state automatically; generic and custom-schema decoding consumes input:

```solidity
function deposit(
    bytes calldata context
) external onlyCommand returns (bytes memory, uint) {
    Execution memory exec = openCommand(context, descriptor);

    while (exec.more()) {
        (bytes32 asset, uint amount) = exec.unpackAmount();
        amount = deposit(exec.account, asset, amount); // host policy hook
        exec.outputBalance(asset, amount);
    }

    return exec.close();
}
```

A command announces itself when the host is deployed. Its constructor emits a
discovery event carrying a packed descriptor with the input, state, and output
lanes, derived block sizes, and flags, plus a human-readable label:

```solidity
abstract contract MyCommand is CommandBase {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("myCommand", Specs.Empty, Specs.Amount, Specs.Balance, 0);
    }

    function myCommand(
        bytes calldata context
    ) external onlyCommand returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, descriptor);
        while (exec.more()) {
            (bytes32 asset, uint amount) = exec.unpackAmount();
            // Apply command-specific behavior for this block.
            exec.outputBalance(asset, amount);
        }
        return exec.close();
    }
}
```

Callback runners in `CommandBase`, `PortBase`, and `QueryBase` can replace the standard lifecycle:
`runCommand(context, descriptor, callback)` processes command batches,
`runCommandOnce(context, descriptor, callback)` invokes its callback exactly once,
`runPort(input, descriptor, callback)` processes port batches and returns output plus
remaining value credit, and `runQuery(input, descriptor, callback)` processes queries
through an `internal view` callback and returns only response bytes. Each callback
receives the shared `Execution memory`. Batch callbacks must consume an item on
every invocation; `runCommandOnce` also invokes its callback for empty sources and rejects
leftover data afterward. Entry-point access modifiers remain in place.

Use `<endpoint>One` for per-item private callbacks, such as `depositOne` and
`portCreditAccountOne`, and `<endpoint>Once` for whole-input callbacks passed to
`runCommandOnce`, such as `relayPayableOnce`. Endpoint-specific names allow composing
endpoint mixins: Solidity rejects
conflicting private callback signatures in multiple base contracts. Keep explicit
opening and closing for custom lifecycle work, such as admin authorization before
processing or pipe settlement after the entire batch.

Deposit hooks return the actual amount that becomes live `#balance` state.
Implementations can therefore deduct external ingress fees or report an
otherwise adjusted received amount without overstating the value passed to the
next pipeline step. Account debits are exact internal bookkeeping operations:
they must make the complete requested amount available or revert. Any account
fee is charged in addition and does not reduce the resulting balance.

Commands can describe grouped lanes with `GroupsAnnot`, available through
`Core.sol` and `Commands.sol`:

```solidity
annotateGroups(id, "#state as (debit, credit), #output as (receipt, change)");
```

Only grouped lanes are listed. Their schemas come from the descriptor; empty
lanes remain empty. Counts and roles are off-chain hints, with no descriptor
fields or runtime enforcement. An empty description clears previous hints.

Commands can publish execution estimates with `ExecutionCost`, available
through `Core.sol` and `Commands.sol`:

```solidity
executionCost(id, 10_000, 5_000); // base cost per invocation, additional cost per batch
```

This emits `#executionCost { uint base, uint batch }`. Estimated command cost is
`base + batch * batchCount`, in destination-local execution units. A batch is one
logical group processed by the command; grouped inputs count as one batch, not
one per constituent block. The concrete host supplies estimates for its hooks.
Pipeline and transport overhead, plus any safety margin, are added separately
by the planner or destination adapter. These are advisory estimates, not enforced
limits or guaranteed bounds. Unknown batch counts or missing annotations mean
unknown cost. The latest trusted annotation replaces the previous estimate;
zero values are valid estimates and do not clear metadata.

Commands can adjust their output allocation hint before the first output reservation
with `exec.scaleOutput(numerator, denominator)`: use `(3, 1)` for three times the
capacity or `(1, 2)` for half. This changes only the capacity hint and allocates
no backing buffer. Division rounds down; zero numerator clears the hint and later
writes still grow normally. Zero denominators, overflowing products or capacities,
and calls after output reservation revert. It does not change descriptor metadata,
input grouping, or the number of blocks the command may emit.

The final argument is a packed flags byte. Pass `0` for an ordinary endpoint,
or compose values such as `Flags.Funded`, `Flags.Admin`, and
`Flags.AdminFunded` from the command or endpoint package entry point.
The same flags byte is copied into the endpoint ID, keeping runtime behavior and
published descriptor metadata aligned. `Flags.Handoff` marks a command that
takes ownership of the remaining pipeline, while `Flags.HandoffFunded` combines
handoff behavior with native-value funding;
bit 6 remains endpoint-defined, and bits 2 through 5 remain reserved.

`CashoutHook` declares an abstract `cashout(account, amount)` hook. Hosts implement
their payout policy and choose the accounting and events to emit. The hook has
no `ChainAsset` or `SpentEvent` inheritance.

The free `sendChainAsset(account, amount)` helper in `core/Cash.sol`, also exported
by `Core.sol` and `Endpoints.sol`, transfers the exact amount to
`Accounts.addr(account)`, accepting EVM-backed account subtypes with a nonzero
address. Failed transfers revert with the global `SendFailed()` error without
copying recipient return data. Zero amounts still validate the account and call
the recipient; hook implementations may skip zero amounts before calling.
The helper performs no bookkeeping and emits no events. The host must authorize
and fund the withdrawal, finalize accounting before calling it, and protect its
entrypoints against reentrancy.

The standard commands cover the common ledger movements: `bootstrap` (source
an initial balance and native-value budget), `cashout` (withdraw native
`#balance` state), `deposit` and
`depositPayable` (external funds in), `settlePayable` (funded settlement),
`withdraw` and `burn` (funds out),
`debitAccount` and `creditAccount` (internal movements), `payout` (deliver
state to other accounts), `realize` (pass each position to
`realize(account, position)`; the hook fulfills it in the existing denominations and
returns counterparty zero; input is empty, and an optional following
`checkPosition` validates the result against POSITION_LIMITS),
`allocate` (turn balance state
into custody),
`provision` (provision custody from an external allocation),
`checkBalance` (validate each balance's asset and amount against paired ASSET_LIMITS
and return it unchanged; `ExecuteCheckBalance` validates memory state directly),
`checkPosition` (validate each position against paired POSITION_LIMITS and return it unchanged;
`ExecuteCheckPosition` validates memory state directly), `settle` (consume
asset-liability position state with empty input, including
Rootzero-backed and liability-only positions),
`relayPayable` (relay a pipeline without
state), and `relayBalancePayable` (relay balance state and a pipeline to another
portal).

## Pipelines

A single command is rarely the whole story. A pipeline is a run of `#step`
blocks executed in order within one transaction:

```txt
step { uint cmd, uint value, #bytes as input }
```

Each step names a command, the native value it may spend, and its input.
The returned state threads into the next command and the final state must be
empty. Each returned native credit replenishes the budget before running the
next step, allowing one command to fund later commands. The standard
`bootstrap` command consumes a stream of
`#bootstrap { bytes32 asset, uint amount, uint budget }` requests and atomically
debits each asset through the standard account hook, introduces matching
`#balance` state, and debits each nonzero budget contribution from the account's
chain asset through the same hook. Its pipeline-local implementation uses assigned step value first when
bootstrapping the chain asset, debits any remainder from the account, and
returns unused assigned value as credit. Bootstrap is registered with command
metadata but is only executable through local pipeline execution. This is the core of
`Pipeline.pipe`:

```solidity
uint cursor;
assembly ("memory-safe") {
    cursor := or(steps.offset, shl(32, add(steps.offset, steps.length)))
}
while (uint32(cursor) < uint32(cursor >> 32)) {
    uint cmd;
    uint value;
    (cmd, value, cursor) = takeStep(cursor);
    if (value > budget) revert InsufficientValue();
    unchecked { budget -= value; }
    (state, value, cursor) = run(cmd, account, state, value, cursor);
    budget += value;
}
if (state.length != 0) revert UnexpectedState();
```

`Pipeline.pipe` takes the available native-value budget as a `uint` and returns
the remaining budget after every step has executed. The enclosing entrypoint
settles that final value once.

`portPipePayable` shares one native-value budget across all supplied CONTEXT
blocks. After all contexts execute, it calls `cashin` once for any nonzero
remainder, crediting the last context's account, and returns zero native credit.
Context ordering determines the recipient. Empty input with value passes the
zero account to `cashin`; account validation belongs to the host's `CashinHook`.
An exhausted or zero budget skips the hook.

The EVM pipeline is deliberately coupled to the canonical wire layout for gas
efficiency. It extracts command selectors, targets, and flags directly from
command IDs and writes CONTEXT, BYTES, and RELAY blocks directly in assembly.
Any change to those ID fields or block encodings must update `Pipeline` at the
same time; the general node and block helpers are not used on this hot path.

A handoff command retains the ordinary command subtype and carries
`Flags.Handoff` in both its ID and descriptor. The reserved handoff envelope is:

```txt
relay { #bytes as input, #bytes as steps }
```

`input` is the handoff STEP's ordinary command input, while `steps` is the
untouched remainder of the original pipeline. `Pipeline.pipe` constructs this
envelope automatically for commands carrying `Flags.Handoff`, calls the command,
and stops executing the transferred continuation locally. Pipeline authors
therefore encode only the command's ordinary input in the handoff STEP. Relay
implementations can publish a qualified `relay.input` schema to describe how
offchain tooling should decode the ordinary keyed blocks inside that byte
payload. Implementations can use `Blocks.exact` for exactly one block, or open
the standard decoder and close it after consuming a batch. The standard relay
commands pass the account and this input to their transport hook alongside a
fully constructed canonical `#context` containing the account, forwarded state,
and remaining steps, plus the handoff command's funds. The transport can
therefore use the account directly and forward the context without
reconstructing its protocol payload.

Handoff has four operational rules:

- A host-local `execute` hook must return `handled = false` for handoff command
  IDs. The hook sees only ordinary STEP input; delegation lets `Pipeline`
  construct the RELAY envelope containing the continuation.
- Handoff transfers STEP bytes, not the pipeline's complete native-value
  budget. The handoff command receives its assigned STEP value. Returned credit
  rejoins the source budget, and the enclosing source entrypoint settles the
  final remainder normally.
- The handoff command must consume or forward the current state and return empty
  state. Because the continuation is no longer executed locally, returned
  non-empty state fails pipeline finalization with `UnexpectedState`.
- A transport that completes asynchronously should relinquish only state that
  is safe before destination success is known. The standard relay commands are
  intended for empty or balance state; debt, position, and similarly fallible
  state must not be relayed this way.

A transfer, for instance, is a two-step pipeline: `debitAccount` turns an
`#amount` input into `#balance` state, and `payout` consumes that state
toward a recipient. Because a pipeline is just blocks, it is also the unit of
command batching. A step's plain `uint value` is drawn directly from the shared
native-value budget. Transport envelopes retain separate opaque, packed
chain-specific `resources` fields for adapters that also need gas or runtime
parameters. A `resources` word is never itself native value; EVM adapters use
`useResourceValue` to extract its low 128-bit value lane before spending it.

Hosts that implement a pipeline locally can inherit `ExecuteBootstrap`,
`ExecuteCashout`, `ExecuteDebitAccount`, `ExecuteCreditAccount`, and
`ExecuteSettle` to register canonical command metadata while executing
their local command IDs through `executeBootstrap`, `executeCashout`,
`executeDebitAccount`, `executeCreditAccount`, and `executeSettle`. The bootstrap and debit adapters decode fixed-stride calldata
input directly; cashout, credit, and settle decode memory-backed pipeline
state. All return `handled = true` and avoid an
external self-call. The host's `execute` hook must authorize a command before
returning true. Returning `handled = false` delegates a local command to its
trusted normal external entrypoint. Pass the step value into each adapter.
Bootstrap is pipeline-local rather than an
externally callable command and may consume value for chain-asset balance;
the other four return assigned value unused as pipeline credit. Their external
command entrypoints remain nonpayable.

`ExecuteAuthorize` extends `Authorize` with an `executeAuthorize` adapter for
NODE input and empty state, returning assigned value unused as pipeline credit. It checks
`enforceAdmin(account, address(this))` internally; the default `Host` policy
therefore requires a self-managed host. Pipeline entrypoints must authenticate
the account and prevent peer-supplied admin accounts. Dispatching `authorizeId()`
directly to this adapter keeps local authorization available independently of
the node allowlist. The external `authorize` endpoint retains its caller checks.

Positions also support backward-composed pipelines. In an exact-output route,
the asset side can represent the desired result while the liability side
represents the value currently required upstream. Each hop consumes one
position, fulfills or transforms its current requirement, and returns the next
position:

```txt
position(C, 100, C, 100)
→ position(C, 100, B, 50)
→ position(C, 100, A, 25)
→ settle()
```

This is backward composition, not backward execution: `#step` blocks still
execute forward in their encoded order. Exact-output routing is only one use;
other commands may transform the asset side, the liability side, or both.

## Queries

Queries are the read endpoints: view functions that take a block-stream input
and return a block-stream response, with the same batch shape as commands. The
standard `getBalance` query takes a run of account-asset positions
and answers each one in order. Query the host's own holdings by supplying its
deterministic host account:


```txt
input:  accountAsset { bytes32 account, bytes32 asset }
response: accountAmount { bytes32 account, bytes32 asset, uint amount }
```

Like commands, every query announces a descriptor at deployment; tooling resolves
the descriptor's lanes through the published block schemas.

## Ports

Settlement and the book port share `BookHook` from `core/Settlement.sol`:
`book(from, to, asset, amount, liability, debt)`. `Settlement` implements it by
debiting `debt` from `from` before crediting `amount` to `to`, skipping zero
amounts. Matching accounts or assets are not netted. Hosts may implement the
hook directly while preserving those exact-leg and funding requirements.
Settlement also calls it for both exact exchange transfers, liability first.

`Calls.raw` and `Calls.rawCopy` (from `Core.sol`) call ports returning
`(bytes output, uint credit)`, using memory and calldata input respectively.
They take `(selector, target, value, input, expectEmpty)`, strictly decode the
tuple, and preserve target failures in `FailedCall`. `expectEmpty` constrains
the output bytes only. Callers authorize the target and must ensure returned
credit is backed before adding it to their budget; the helpers do not transfer
ETH back. All ports return this tuple. Nonpayable ports return zero credit;
`portDispatchPayable` returns its unspent budget. `portPipePayable` settles its
remainder through `cashin` and returns zero credit.
`Calls.rawQuery` decodes bytes-only query results. `Calls.tryRaw` and
`Calls.tryRawCopy` report call success without decoding returndata, with optional
explicit gas limits. All `Calls` functions are internal library helpers.

`exec.rawCall(selector, target, value, input, expectEmpty)` and
`exec.rawCallCopy(...)` provide the same calls with execution budget accounting.
They debit the full-width native `uint value` before calling, add the returned
trusted credit to `exec.budget`, and return only the output bytes. Callers with
packed resources pass `uint128(resources)` to extract the EVM value lane.
Target authorization and credit backing remain the caller's responsibility.

Ports are the host-to-host surfaces, callable only by trusted peer hosts.
**A trusted peer is a fully trusted extension of the receiving host.** Admitting
a peer authorizes it to use every port the host exposes. Peer trust is not a
limited permission to perform selected operations.

Before admission, the host's maintainers must fully validate the peer's behavior
against the host's invariants, including its externally reachable entrypoints,
dependencies, and upgrade authority. The peer must prevent its callers from
causing unauthorized or invalid actions on the receiving host. For example, a
peer that credits backing must establish that backing before calling the credit
port. The receiving host relies on that guarantee instead of proving it again
for each operation. Changes to the peer or its dependencies require renewed
validation of the trust decision.

The port authenticates the peer once at entry through `onlyPeer`. There is no
additional peer-specific authorization by port, asset, direction, or individual
operation inside the batch. This keeps repeated authorization out of the
execution path. Parsing, balance sufficiency, arithmetic checks, and other
operation invariants still apply; they establish validity, not different
permissions for different trusted peers. A component that cannot be trusted
with the full port surface must not be admitted as a trusted peer.

The central ports are batches all the way down:

- `portRequestAsset` consumes `amount { bytes32 asset, uint amount }` blocks and
  passes the authenticated peer, asset, and amount to a host hook. The hook
  validates asset support and applies the host's request and transfer policy.
- `portRequestAllowance` consumes the same amount blocks and lets the
  authenticated peer set its own asset allowance through the same authoritative
  hook used by the admin allowance command.
- `portBook` consumes a flat stream of paired `accountAmount` blocks: debit
  account/liability/debt first, then credit account/asset/amount. Its descriptor
  declares ACCOUNT_AMOUNT input and it publishes `#input as (debit, credit)`
  through `GroupsAnnot` on the port ID, without a custom parent block.
  Both accounts may be the same for booking. It returns empty bytes and zero credit, and any
  incomplete pair, malformed block, or account-hook failure reverts the entire batch.
  Both legs are decoded before calling `BookHook`; zero amounts skip their legs.
  For transfers, use the same asset and amount on both sides. For a single-sided
  entry, explicitly set the omitted leg to zero debt or amount; a zero account
  alone does not omit a leg. The `Tx` struct and transaction helpers
  remain available, but this port consumes paired `accountAmount` blocks.
- `portCreditAccount` and `portDebitAccount` consume `accountAmount` blocks
  and apply the operation to the specified account. To credit or debit a host,
  pass `Accounts.toHost(host)` as that account. The same account hooks handle both.
- `portPipePayable` consumes `context` blocks, each carrying an account, an
  initial state, and a run of steps — a complete pipeline delivered by another
  host, executed locally against the port call's shared value budget.

This is also the cross-portal mechanism. `relayPayable` and
`relayBalancePayable` are handoff commands whose transport hooks decode their
own destination and resource input and forward an already constructed command
context, while `portDispatchPayable` dispatches an explicit portal payload. A
`Portal` forwards ordinary incoming CONTEXT streams directly to its commander
host's `portPipePayable` endpoint. The pipeline port settles any remainder to
the last context's account and returns zero credit. The portal ignores successful
return data and does not decode the message or perform account settlement.
Failed messages are retained by digest and may be replayed through a separately
selected trusted recovery-handler port. A
bridge adapter moves the **raw
bytes**; the destination host parses them with the same cursor rules and runs
the same pipeline loop. Nothing in the payload is EVM-specific — step commands
are destination-local command IDs, and only the adapter boundary (native
transfers, address resolution, signatures) is chain-specific. The parity rule
for ports is strict: every chain's implementation must parse the same input
bytes and produce the same output bytes for every endpoint.

## Guards and Admin

Admin commands use the regular command shape but are gated to the host's admin
account: trust management (`authorize`, `unauthorize`), guardian management
(`appoint`, `dismiss`), metadata (`annotate`), optional asset gating
(`allowAsset`, `denyAsset`, `allowance`), and raw calls (`executePayable`).
Guards go the other way: direct actions guardians can take
without any command context — the default is `revoke`, which lets a guardian
drop a trusted node immediately.

## Events and Discovery

Hosts are self-describing. At deployment a host emits the ABI of every event it
uses (`EventAbi`), block schema events, endpoint descriptors, and labels for
human-readable names. State changes then follow evented
conventions: `Balance` for account ledger changes (including host accounts),
and flow events (`Received`,
`Spent`, `Locked`, `Unlocked`) for value movement, each tagged with the endpoint that
caused it. An indexer can reconstruct the entire repository — endpoints,
names, access sets, balances — from logs alone, with no artifact files.

## Development

For repository development, `npm test` runs regular tests without the
`*.bench.test.ts` suites. Run a focused test with
`npm test -- test/peer.test.ts`, or filter the regular suite with
`npm test -- --grep "Port Entrypoints"`.

Run `npm run bench` for benchmarks, or
`npm run bench -- test/settlement.bench.test.ts` for a specific benchmark.
Use benchmarks for performance changes, baseline updates, and release checks.
`npm run test:all` runs the complete suite. `npm run typecheck` checks TypeScript.
Use `npm test -- --list` or `npm run bench -- --list` to inspect suite selection.

## Using the Library

Import from the package entry points rather than deep paths:

- `@rootzero/contracts/Core.sol` — `Host`, annotation helpers including
  `CounterpartyAnnot`, access control, `Balances`, `Settlement`, `ExecuteHook`,
  `PipeHook`, `ForwardHook`, `Pipeline`, `Portal`, validator
- `@rootzero/contracts/Commands.sol` — `CommandBase`, `Execution`, `Flags`,
  annotation and codec helpers, and shared value types for authoring custom commands
- `@rootzero/contracts/Endpoints.sol` — command, admin, port, guard, and query
  mixins, their hooks (including `ExecuteHook` and `PipeHook`), and `Flags`
- `@rootzero/contracts/Codec.sol` — `Blocks`, calldata `Cur`/`Cursors`, memory
  `Memory`, `Writers`, `Schemas`, `Execution`/`Executions`, `Flags`, `Keys`, and
  `Specs`
- `@rootzero/contracts/Utils.sol` — `Ids`, `Nodes`, `Assets`, `Accounts`,
  cursor, layout, and value helpers
- `@rootzero/contracts/Events.sol` — protocol event contracts

`Core.sol`, `Commands.sol`, `Endpoints.sol`, and `Utils.sol` each export all
shared protocol errors from `utils/Errors.sol`, including `QueryFailed` and
`SendFailed`. Core-specific errors such as `AccessDenied` and `FailedCall`
are exported by `Core.sol`.

Repo layout:

- `contracts/core` — host, access control, balances, pipeline, validation
- `contracts/commands` — standard commands and admin commands
- `contracts/ports` — port surfaces for inter-host and cross-portal flows
- `contracts/guards` — guardian direct actions
- `contracts/queries` — read-only query endpoints
- `contracts/codec` — block schemas, cursor parsing, buffers, and writers
- `contracts/utils` — ids, nodes, assets, accounts, layout, ECDSA
- `contracts/events` — event contracts and emitters
- `docs` — [`Schema.md`](https://github.com/lastqubit/rootzero-evm/blob/main/docs/Schema.md) (wire format and schema DSL)

Use this library to create a new rootzero host, implement a command, or reuse
the protocol's block format in tooling. It is the shared protocol foundation,
not an end-user application.
