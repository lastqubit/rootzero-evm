# Indexing

> Historical experiment suites referenced below have been retired. Recorded
> measurements are retained; see [the current core benchmarks](../README.md#development)
> for the supported benchmark commands.

The canonical event layouts are documented at the top of
[`contracts/codec/Logs.sol`](../contracts/codec/Logs.sol). Standard protocol events
use LOG0 with no topics. Every event starts with one category byte. Its header is
category-specific and is **not** a standard block header.

## Event categories

All fields below are 32-byte big-endian words unless marked otherwise. `blocks`
means an ordinary `[key:4][payload length:4][payload]` stream without ABI padding.
`name` is variable-length raw text, not a 32-byte field.

| Category | Name | Fields after category | Total bytes |
|---|---|---|---|
| `0x01` | Access | node, enabled flag:1 | 34 |
| `0x02` | Introduction | peer, origin account, claimed block number, name | 97 + name bytes |
| `0x03` | Metadata | subject, blocks | 33 + blocks |
| `0x04` | Execution | endpoint, account, selected STATE/INPUT/OUTPUT blocks | 65 + blocks |
| `0x05` | Endpoint | endpoint, stateSpec, inputSpec, outputSpec, name | 129 + name bytes |
| `0x06` | Reserved | Former Pipeline category; never reuse | - |
| `0x07` | Balance | account, asset, actual balance | 97 |
| `0x08` | Envelope | portal, resources, key, digest | 129 |
| `0x09` | Resolution | key, digest, resolved flag:1 | 66 |

Zero is reserved. Unknown categories must be preserved or skipped, never parsed
as another header. Reject incorrect lengths for known fixed layouts and truncated
headers for variable layouts. A category identifies a stable wire layout;
incompatible layouts get a new category value rather than inserting header fields.

Index records by chain, emitter, transaction and log index. The emitter is the
publisher, not necessarily the subject. Apply application trust policy to every
claim; category bytes do not establish authority. Ordinary ABI events from hooks
retain their topics and are outside this category system.

## Discovery names

Names in Introduction and Endpoint records are trailing raw UTF-8 bytes, with
no length field, block wrapper or padding. The remaining event bytes are the name.
An Introduction name describes the peer, not the emitter. Names are self-declared,
nonunique discovery hints; host and endpoint IDs remain the identifiers. A host
without an introduction has no onchain name and is identified by its host ID.
Repeated introductions may publish another hint; they do not rename an identity
or grant access. Indexers retain provenance and apply their own display overrides.

## Node access

Access records explicit node authorization transitions: `[0x01][node:32][enabled:1]`. The emitting host owns the authorization; enabled is exactly 0 or 1. Repeated grants or revocations without a change emit no Access record. The host implements this through `setAccess(uint node, bool enabled)`; internal mutation calls emit too. `authorize`, `unauthorize`, the `revoke` guard and internal authorization adapter rely on these Access events, with execution logging disabled (no logging bits in their IDs). Empty and unchanged batches emit no Access or Execution records. Guardians and account permissions remain outside this category.

## Endpoint discovery

`Logs.endpoint(id, state, input, output, name)` publishes an Endpoint
record with four fixed words followed by the registration name. There is no codes prefix or ENDPOINT block wrapper. The standard ENDPOINT
block codec remains available for block-based data; do not confuse its header
with the event header. Specs are pure specifications, without embedded codes.

Decode endpoint ID kind, selector, address and public behavior flags using the
node layout. Register the specs and policy under `(chain, emitter, endpoint ID)`.
Behavior and logging flags are both part of the ID. Query endpoints
are registered normally but do not emit execution records.

## Execution records

```text
[0x04][endpoint:32][account:32][STATE?][INPUT?][OUTPUT?]
```

Each logged invocation emits one completion record, including empty batches.
Selected empty containers retain their eight-byte block headers. Callback and
nested execution logs precede the containing completion record. Reverts discard
all records, including earlier hook logs from that reverted invocation.

The account is the active context account for commands. Guards derive the acting
account with `Accounts.toUser(msg.sender)` after guardian authorization and before
opening the buffer. Ports default to zero, meaning no acting account is attributed;
a port implementation can explicitly supply an account through the `runPort`
overload. The peer address is not automatically treated as an acting account.
Affected subjects can differ from this account and remain in the lane blocks.

Source lanes are snapshots from opening. Output is the callback result. They share
one growable memory buffer; emission precedes returning its output region in place.
External Solidity ABI return encoding still applies. Returned bytes contain only
output blocks, not the category or event header.

### Execution policy

Pass a single lane flag directly at registration, such as `Logs.Input`.
For combined lanes, a named constant keeps the policy readable:

```solidity
uint private constant FLAGS = Logs.State | Logs.Output;
// Constructor:
(id, descriptor) = command("realize", Specs.Position, Specs.Empty, Specs.Position, FLAGS);
```

The endpoint ID flags byte is at bits 224..231. Bit 0 is Funded, bit 1 Admin,
bit 2 logging Execution, bits 3/4/5 State/Input/Output, bit 6 endpoint-defined,
and bit 7 Handoff. `Logs.Execution=4`, `Logs.State=12`, `Logs.Input=20`, `Logs.Output=36`.
Every lane flag includes Execution. Combine flags at registration, for example
`Logs.Input | Flags.Admin`. No logging bits means no record or buffer preparation.
Lane bits without Execution, or flags exceeding one byte, are rejected. Ports cannot
select state; guards allow only input logging. `Logs.Execution` alone logs the header.

There is no separate logging field in Endpoint events. Endpoint IDs and logging policy are fixed at deployment. `Logs.Execution=4` is
both the event category and the header-only logging flag. Other category values
are identifiers, not logging flags. Access and indexing use the complete ID.

### Offchain interpretation

Endpoint and Envelope events carry no semantic codes. Tags, action names and
custom state effects belong in a versioned offchain registry keyed by chain,
endpoint and applicable block range. The endpoint identifies its host; the event
emitter supplies provenance. Retain raw events and schemas so projections can be
rebuilt as interpretations change. Unknown endpoints remain browsable typed data.

For example, a registry may interpret INPUT asset blocks from an allowAsset
endpoint as allowed assets. That interpretation relies on the implementation's
promised effect; input data alone does not prove it. Core Access and Balance events
retain their category-defined state meaning. Asset and entity code queries have been removed. Normal application reads come
from indexer projections; `GetBalance` and `GetQuote` are the built-in queries. `QueryBase`
remains available for specific custom direct reads. The CODES block API and
onchain classification vocabularies have been removed.

## Metadata

```text
[0x03][subject:32][standard blocks...]
```

`Logs.metadata(subject, data)` publishes one or more blocks about one subject.
There is no ANNOTATION wrapper, BYTES wrapper or codes prefix in this event.
SCHEMA, LANE and COUNTERPARTY are distinct standard blocks.
Schemas describe block structure; lanes describe homogeneous block sequences.
LANE has payload `uint lane, #string as body`. The low 32 bits of `lane` identify
the host-local description; the remaining spec fields identify the actual blocks.
Endpoint discovery retains the packed lane words. A zero lane key needs no lookup.
Asset preimages can be published as metadata about the asset.

Trust and merge rules belong to the block type. Schema claims are keyed by subject
and the block key in the spec. The latest trusted
claim replaces the previous claim for that key. Lane claims are independently
keyed by subject (host) and the low 32-bit lane key. Their spec must match the
endpoint lane spec. The latest trusted claim replaces the previous one; an empty
body clears grouping hints. Invalid bodies and conflicting specs are reported,
not silently replaced with older claims.
A COUNTERPARTY value of zero identifies Rootzero, not a deletion.

General labels and annotations are maintained offchain. The admin `annotate`
command and LABEL/ANNOTATION blocks are removed. Contracts still publish schemas
and other structured metadata directly. Gas estimates and command execution costs
are also maintained offchain.

The retired `named-discovery.bench.test.ts` compared registration helpers with
identical endpoint fields and names. Combining the Endpoint record and its former
LABEL Metadata record saves 1,308 gas for `deposit` (seven name bytes), with one
record instead of two. Tested names from zero through 128 bytes save 1,308 to 1,333
gas. These are helper execution measurements, not full deployment gas.

## Balance records

The compound identity of a balance is `(host, account, asset)`. Derive the host
identity from the chain and event emitter address, giving an equivalent database
key of `(chain, emitter, account, asset)`. The same account can hold the same asset
on multiple hosts; these are independent balances and must remain separate rows.
Each Balance record replaces the value for exactly that compound identity.
It is not a delta and must not be added to execution amounts.
Hook implementers call `Logs.balance` after a successful nonzero credit/debit,
including a resulting zero balance. Zero-amount mutations need not emit.
The ACCOUNT_BALANCE block remains the query/output schema, but the Balance event
has fixed fields with no block wrapper or codes.

Pipeline entry emits no event. Execution records identify their own accounts,
and Balance records capture actual balance changes. Category 6 remains reserved
for historical Pipeline events; initial budgets are not indexed as balances.

## Introduction and transport

Introductions contain a peer, the origin account, a claimed block number and
the peer's discovery name. `Logs.introduction(peer, origin, blocknum, name)`
emits the record; `introduce(peer, blocknum, name)` validates the caller.
They do not grant authorization or prove deployment timing. The receiving host is
the emitter; application trust determines which introduction claims to accept.

Envelopes contain destination portal, chain-specific resources, correlation key,
and message digest. The helper describes an operation;
it does not send a message or spend resources.

Resolutions use a final byte of exactly 0 for unresolved or 1 for resolved. Index
recovery state by chain, emitting host and key, and retain the digest. Missing
records are not evidence of resolution. A successful recovery consumes the stored
record; failed witness validation or later reverts roll the operation back.

## Compatibility

These category events are a breaking change from untagged ID/codes-prefixed logs.
Select decoders by deployment/version; do not guess old formats from a byte that
coincidentally matches a new category. There is no implicit backwards-compatible
fallback. Historical benchmark fixtures retain their original event encodings.

The public helpers are access, execution, endpoint, balance, metadata,
introduction, envelope and resolution. Untagged mem/copy/wrap and correlated stream
helpers are retired from production. Standard blocks remain usable independently
of event headers, except the removed execution-cost and action blocks.

### Historical v1.51 Bootstrap shared output and reserved log space

These measurements describe v1.51, preserved in the test-only BootstrapLogged151
fixture. Production Bootstrap now relies on hook-owned AccountBalance logging.

The v1.51 implementation validates the outer BOOTSTRAP and final LIST together,
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
  against the frozen v1.51 BootstrapLogged151 adapter. It includes decoding, allocation,
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

The hybrid was adopted before the v1.51 shared-allocation optimization, tested through
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
benchmark now uses the frozen v1.51 adapter for CommanderCurrentBootstrap; the
other frozen candidates retain their earlier code. Production Bootstrap no longer
emits this debit stream.

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
