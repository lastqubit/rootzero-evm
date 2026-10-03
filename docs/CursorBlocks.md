# Blocks (formerly CursorBlocks)

Header constants now live in `codec/Headers.sol` as `Headers`, using `uint`.
Import through Codec/Commands or directly; `Specs.sol` no longer exports Headers.
The former uint64 constants are isolated in the test-only `LegacyHeaders`.

The cursor implementation is now `contracts/codec/Blocks.sol`, library `Blocks`.
Import `Blocks` from `Codec.sol`, `Commands.sol`, or the codec file directly.
The former absolute-position Blocks and Memory libraries are removed from the
production API. Frozen `LegacyBlocks` and `LegacyMemory` remain under
`contracts/test` for historical tests and benchmarks, outside the published package.
The experiments below retain their historical names and measurements.

`unpackStatus`, `unpackHostAmount`, and `unpackHostAccountAmount` use the generic
fixed-word primitives. Each checks the exact header and complete containment,
returns values followed by `nextCur`, and preserves source bounds.

Raw `expect1/2/4/8/16/32(abs, value)` helpers sit immediately after the readers.
They compose the corresponding reader and revert `UnexpectedValue` on mismatch.
They do not check bounds or advance a cursor: callers establish the logical
range first, and reads beyond physical calldata use EVM zero-padding.

## Current consuming API

Execution's ordinary fixed and composite unpackers now delegate to Blocks
and assign its returned cursor to the appropriate input or state lane. Constraint
expectations follow the same pattern. Scalar word decoders cover 32/64/96/128/160
payload bytes; named fixed decoders follow by size, then composite decoders and
expectations. Struct-value Execution adapters reuse their scalar counterparts.

Named dynamic Execution unpackers return payload cursors, including Bytes,
String, Relay, Annotation, Label, Schema, Context, Step, Call, Dispatch and
Recover. Convert with toBytes/toString only at a hook, event or other consumer
that needs a calldata view. The old unpackRaw adapter has been removed.
Opening and budget handling remain Execution-specific. Whole-stream selectors
delegate validation to Blocks and mark the corresponding lane consumed.

Validation order is parent header, parent containment, then child shape or
constraint values. This can change the error for multiply-invalid input: a bad
fixed header wins over truncation; a truncated composite parent wins over a bad
child header. No wrapper repeats these validations.


```solidity
(blockCur, cur) = Blocks.take(cur, keyOrSpec);
(blockCur, cur) = Blocks.takeFixed(cur, header);
blockCur = Blocks.takeExact(cur, spec);
(payloadCur, cur) = Blocks.unpack(cur, keyOrSpec);
(abs, payloadCur, cur) = Blocks.enter(cur, keyOrSpec, amount);
(abs, payloadCur, cur) = Blocks.enterFixed(cur, header, amount);
(abs, payloadCur) = Blocks.enterExact(cur, spec, amount);
(payloadCur, cur) = Blocks.unpackFixed(cur, header);
payloadCur = Blocks.unpackExact(cur, spec);
```

All take overloads (including take(cur)) return the advanced source cursor last.
Source cursors have zero upper bits; the advanced source retains its original end. Prefix enter returns the original payload start,
the remainder after the validated prefix, and the source after the entire block.
It does not depend on how much of the selected child range the caller consumes.
The two-argument enter overloads have been removed; use unpack instead.
The consuming helpers are grouped as enter/enterFixed, take/takeFixed, then
unpack/unpackFixed and named unpackers. enterFixed reuses expectHeader and the
prefix primitive; unpackFixed reuses takeFixed and skips its validated header.
Both preserve the enclosing source end and check headers before bounds.
takeExact and unpackExact validate that one block fills the entire range. They
return a clean block or payload cursor without a nextCur. unpackExact skips the
header after takeExact validates it; neither repeats checks. enterExact reuses
unpackExact, checks only the requested prefix length, and returns its original
payload address plus the remaining payload cursor. Oversized prefixes revert
InvalidBlock; skipping the complete payload is valid.
With solc 0.8.35, viaIR and optimizer 200, the composed STEP consumer has
identical executable runtime bytecode before and after replacing exact with
unpackExact/takeExact (1,488 bytes excluding compiler metadata). The wrapper
composition adds no runtime gas cost in that consumer.
The older API descriptions and measurements below are experiment history;
this section describes the current selection/entry signatures.

`Executions.unpackList(exec)` consumes a LIST through `Blocks.unpackList`
and returns its payload as a `uint`. The custom-spec overload uses `unpack`.
Both update `exec.input` directly; neither allocates a `Cur` memory wrapper or
repeats the enclosing block checks. Empty payloads are valid where the spec
allows them. Child decoders must retain their returned next cursor explicitly,
because packed cursors are passed by value. The List and Swap examples show
this pattern; Swap also uses `unpackExact` for the final BYTES child of each hop.
Swap configuration and hop structs retain hook data as `uint hookDataCur`. No
memory byte arrays are created for unused hook data; consumers can use `toBytes`
when they actually need a calldata view.

Execution selectors mirror the library's enter, take, and unpack families,
including Fixed and Exact variants. They assign the advanced source to
`exec.input` internally and return only the selected values. Exact wrappers
mark the validated input range consumed without repeating its bounds check.
`exec.enter(spec, amount)` returns `(abs, payloadCur)` and consumes the entire
parent; decode children with `payloadCur`, not with the execution's next input.
The old two-argument enter, into, and descend APIs are removed. Use unpack for
an entire payload, or enter with a prefix length. Raw byte navigation is
`exec.advance(amount)`, which returns the previous absolute position; take now
always selects a header-inclusive block. The consume, takeBlock and unpackRaw
adapters have been removed: retain selected cursors, convert with toBytes only
when required, and extract uint32 bounds only at interfaces that need them.
absolute and expect(exec, abs) are also removed; inspect uint32(exec.input) or
check consumption of the selected child cursor. Both unpackList overloads remain.

Execution next1/next2/next4/next8/next16/next32 and their private nextN helper are
also removed. Validate a custom block's fixed prefix once with enter, then use
Blocks.read1/read2/read4/read8/read16/read32 at absolute offsets. These
return bytes1/bytes2/bytes4/bytes8/bytes16/bytes32, never advance a cursor, and do
not repeat bounds or schema checks. They accept the full uint256 absolute
position and use EVM zero-padding beyond calldata.

read32 is the underlying load primitive; the smaller readers are thin bytesN
casts of its leading bytes, ordered after it and before comparison helpers.
With solc 0.8.35, viaIR and optimizer 200, the raw-reader harness has identical
executable runtime bytecode (excluding compiler metadata) and equal per-reader
gas estimates to direct calldataload implementations. Verified by
cursor-raw-readers.bench.test.ts.

```solidity
(uint abs, uint payloadCur) = exec.enter(customSpec, 20);
bytes4 selector = Blocks.read4(abs);
bytes16 value = Blocks.read16(abs + 4);
// Decode any children from payloadCur; exec.input already points past the parent.
```

The repository now defaults to Solidity 0.8.35 with viaIR, optimizer 200 runs,
and Cancun. Use the viaIR measurements below for optimization decisions. The
non-viaIR measurements describe the frozen fused reference, not the current
compositional implementation or the default build.

`Blocks` provides bounded selection, payload entry, exact matching, fixed and
composite unpackers, constraint checks, and stream validation/counting.
Executions delegates ordinary decoding to this library. Memory execute-command
adapters live in `Execute`; allocation and writing live in `Encoder`. The old
Decoders and Writers libraries have been removed.


## Historical migration experiments

The remaining sections record successive experiments, including APIs that were
renamed or removed. Code snippets and metadata behavior below describe those
stages, not the current API. Use the current consuming API above and library
NatSpec for current signatures and preconditions.

### Execution migration measurements

Solidity 0.8.35, viaIR, optimizer 200, Cancun. The fixed-decoder fixture includes
dispatch, the returned value encoding, and source advancement on both paths;
these are comparative consumer measurements, not standalone primitive costs.

| Decoder group | Gas change versus old Blocks + cursor advance |
| --- | ---: |
| Scalar fixed decoders (18 types, including Balance) | 41?76 less |
| BalanceConstraints struct decoder | 41 more |
| PositionConstraints struct decoder | 37 more |

The constraint structs use one calldata copy after validation. This was cheaper
than individual high-level assignments, individual assembly stores, or manual
allocation in this fixture. Direct expectBalanceConstraints/expectPositionConstraints
still check calldata directly and do not create those structs.

The legacy Execution comparison also passes converted child payloads back as
calldata, so its composite measurements include conversion. Annotation, Label,
Schema, Call, Dispatch and Recover save 53?71 gas per call; Context and Relay save
90 and 68. These compare against the frozen legacy adapter, not the immediately
preceding working-tree revision. The unpackKeyBounds comparison (formerly consumeKey) measures 18 gas
higher in this fixture; the benchmark reports tradeoffs instead of requiring
every operation to improve.

Run execution-decoders.test.ts for fixed and composite cursor behavior,
execution-decoders.bench.test.ts for the fixed comparison, and
execution-optimization.bench.test.ts for the legacy consumer comparison.

## Cursor contract

Names distinguish representation: `cur` and `...Cur` hold packed cursors;
`abs` and `...Abs` hold absolute calldata byte positions. `endAbs` is an
exclusive absolute boundary, and `nextAbs`
is the next absolute position. Local payload positions simply use `abs`, or
`body` when the helper also needs a separate header position. For example, `take(cur)` accepts a cursor,
while `read32(abs)`, `tail(abs, endAbs, key)`, and `pack(abs, endAbs)` accept
absolute positions. A raw position is never implicitly treated as a cursor.
The source follows dependency order: predicates, absolute-position primitives
and helpers, cursor primitives, selection/scanning helpers, then unpackers and
expectations. Each primitive appears before helpers that call it.
Selection helpers return `blockCur` and `nextCur`; prefix entry returns `abs`,
`payloadCur`, and `nextCur`. Unpackers return the advanced source as `nextCur`, while
decoded child ranges retain field names such as `inputCur` and `stateCur`.

- Bits 0–31: absolute calldata position.
- Bits 32–63: exclusive end.
- Selected ranges ignore input metadata above bit 63 and return zero metadata.
  Every stream unpacker returns decoded values followed by `nextCur`, preserving the
  original source end and metadata, with only the position advanced.
- The caller establishes that the supplied range belongs to calldata. These
  helpers validate containment within that range, not `calldatasize()`.
- Range-returning functions select without advancing the caller's stream.
  Stream unpackers return the advanced source cursor last for the caller to assign;
  exact selectors return no source remainder.
  Every returned range is bounded; consumers need not repeat that check.

| Helper | Result | Validation |
|---|---|---|
| `runCount(cur, key)` | Count only | Hint scan; stops at a different key or incomplete block, without reverting |
| `read1/2/4/8/16/32(abs)` | Raw bytesN value | Unchecked full-width absolute calldata read; caller owns bounds |
| `take(cur)` | Complete block, including header | Complete header and payload fit |
| `take(cur, spec)` | Complete block | Key, minimum/maximum payload size, containment |
| `take(cur, key)` | Complete block | Key and containment |
| `takeFixed(cur, header)` | Complete block | Exact uint64 key/length header and containment |
| `unpack(cur, spec/key)` | Payload and nextCur | Schema/key and containment |
| `enter(cur, spec/key, amount)` | Prefix address, payload remainder, nextCur | Schema/key, containment, prefix length |
| `enterExact(cur, spec, amount)` | Prefix address and payload remainder | Exact block range and prefix length |
| `takeExact(cur, spec)` | Complete block | Schema plus block end equal to source end |
| `unpackExact(cur, spec)` | Payload | Schema plus block end equal to source end |
| `unpack64(cur, key)` | Two bytes32 fields and nextCur | Exact key/64-byte length, containment, then trusted loads |
| `unpackBalance(cur)` | Asset, uint amount, nextCur | Exact BALANCE header, containment, then trusted loads |
| `unpackStep(cur)` | Command, value, INPUT payload cursor, nextCur | Parent key/containment, exact final child header, then trusted fixed-word loads |
| `unpackRelay(cur)` | Input and continuation payload cursors, nextCur | Parent containment, first child key, exact final child proof |
| `unpackContext(cur)` | Account, state/input payload cursors, nextCur | Parent containment, two-child proof, then trusted account load |
| `unpack160(cur, key)` | Five bytes32 words and nextCur | Exact key/160-byte header and containment before trusted loads |
| `expectPositionConstraints(cur, position)` | Advanced source cursor | Exact header, containment, identifiers, then inclusive quantity bounds |

Specification maximum zero means unbounded, consistently with `Blocks.enter`.
An empty payload or a fully skipped prefix returns a valid empty range, not an
absent/zero cursor. `takeFixed` accepts the right-aligned uint64 format used by
`Headers`, rather than a packed specification.

## Trust and advancement

`runCount(cur, key)` is a hint-only exception to validating helpers. It returns
only a count, never an updated cursor. It ignores metadata, returns zero for
empty/reversed ranges, and stops before a different key or a declared block
that exceeds the source boundary. A partial header cannot count as a complete
block, and computed ends stay full-width before comparison. It does not inspect
nested schemas or validate the stream; normal decoding still owns those checks.

```solidity
uint count = CursorBlocks.runCount(cur, Keys.Bytes);
```

`cursor-run.test.ts` compares this behavior with `Blocks.runCount` and a direct
assembly candidate, including malformed trailing blocks and logical truncation.
`cursor-run.bench.test.ts` measures exhausted, nonmatching, and truncated endings
at 0, 1, 32, and 128 matching blocks and payload lengths 0, 1, 33, and 256.
Results are written to `.npm-cache/cursor-run-results.json`.

The selected implementation delegates once to the private absolute-position
`runCountAt(abs, endAbs, key)` primitive. Its loop loads each candidate header
once, tests the key, computes a full-width end, and stops if it exceeds the
boundary. Under Solidity 0.8.35, viaIR, optimizer 200, Cancun it measures
133 gas/matching block, matching `Blocks.runCount` in the same harness. Both
harnesses have 598 runtime bytes. A composed `read32` loop measures 184 and a
single cursor-input assembly loop 154; all candidates remain in tests. These
are incremental scan costs; a stopping header adds fixed overhead.

```solidity
uint blockCur = CursorBlocks.take(exec.decoders, spec);

// Preserve the stream end and state-lane metadata. Blocks proved the new
// position fits, so a checked Cursors.seek would repeat validation.
exec.decoders = (exec.decoders & ~uint(type(uint32).max))
    | uint32(blockCur >> 32);
```

Do not assign `blockCur` directly to the enclosing stream: that would replace
the stream boundary and discard its metadata.

```solidity
uint bodyCur = CursorBlocks.enter(streamCur, parentSpec);
uint childCur = CursorBlocks.take(bodyCur, childSpec);
```

Checking the child against its parent is a new containment guarantee, not a
duplicate check. Likewise, key-only selection does not establish field widths.
Semantic decoders can establish an exact shape once and then perform trusted
field loads. Independently callable field readers still need their own width
preconditions. Complete child consumption remains a separate schema constraint.

The implementation loads a header once and computes a full-width end before
packing. A uint32 start plus uint32 payload length plus 8 cannot overflow uint256;
one `end <= limit` comparison proves header and payload containment. No narrowing
occurs before that check. `enter` is simply `take(cur, spec/key) + 8`: the
containment proof guarantees this cannot carry into the end lane. Under viaIR,
this costs exactly the same gas as directly packing the payload start.
`unpackExact` uses equality instead of a separate containment check followed by equality.

Schema errors use `InvalidBlock`; containment errors use `OutOfBounds`.
Header/schema errors take precedence when both are wrong; prefix length is
checked after containment. `unpackExact` uses `InvalidBlock`
for truncation and trailing data, like `Blocks.exact`. Generic `take` uses
`OutOfBounds`, whereas existing `Blocks.peek` uses `MalformedBlocks`.

## Comparison and verification

The latest complete-consumer comparison is documented under “Complete consumer
flows” below. It measures direct cursor handoff rather than immediately converting
selected cursors back to absolute start/end pairs for an artificial checksum.

The unpacking measurements in the earlier sections below describe the frozen
range-returning API. Its harness variants are now named `RangeReference`, backed
by test-only `RangeCursorBlocks`. They do not measure the current unpacker API.
The final sections and `cursor-uniform`/`cursor-next` benchmarks measure the
advancing API directly. Selection helpers keep their contracts. Constraint expectations now return the
advanced source cursor too; their earlier measurements are labeled historical.

```sh
npm test -- test/cursor-blocks.test.ts
npm run bench -- test/cursor-blocks.bench.test.ts
npm test -- test/cursor-unpack.test.ts
npm run bench -- test/cursor-unpack.bench.test.ts
```

The test harness imports through `Codec.sol`. Correctness comparisons use the
existing `Blocks` helpers with complete-block caller-side containment checks.
The private `Blocks.enterFixed` path is reproduced in the harness because it
cannot be called directly. Tests cover returned ranges, stream metadata,
logical truncation with valid trailing calldata, exactness, schema limits,
prefix boundaries, reversed ranges, uint32 overflow, and nested containment.

The benchmark uses separate tuple and packed producer contracts and equivalent
stream loops. It compares decoded range sizes and final stream words before
reporting gas. No assertion requires the new library to win: the purpose is to
compare further optimization candidates. Results go to the ignored
`.npm-cache/cursor-blocks-results.json` (or `cursor-blocks-results-ir.json` with
`viaIR`), together with the default profile's compiler settings.

Historical incremental gas per block with Solidity 0.8.35, optimizer 200 runs,
Cancun, and `viaIR: false`:

| Operation | Existing bounded pattern | Frozen fused reference | Delta |
|---|---:|---:|---:|
| Exact/ranged schema selection | 509 | 435 | -74 |
| Unbounded schema selection | 498 | 435 | -63 |
| Key selection | 391 | 382 | -9 |
| Fixed-header selection | 305 | 361 | +56 |
| Generic selection | 434 | 321 | -113 |
| Payload entry | 514 | 454 | -60 |
| Payload entry after 16 bytes | 696 | 493 | -203 |

Streams contain 1, 32, or 128 blocks, each with a 32-byte payload. Per-block
slopes must agree across those sizes. Measurements include common loop work
but exclude transaction intrinsic gas, deployment, ABI decoding, and cursor
setup. They are not whole-transaction savings. Compiler inlining and consumer
shape affect the results, so these differ from the earlier isolated prototypes.
The fixed-header regression is an explicit optimization target.

With the same compiler/settings and `viaIR: true`, the corresponding deltas
are -74 (exact/ranged schema), -52 (unbounded schema), +18 (key), +21 (fixed
header), -41 (generic), -74 (entry), and -147 (prefix entry). Thus even the
direction of the key-only comparison depends on compiler lowering. The frozen fused implementation passed correctness tests under both pipelines;
the current shared-primitives implementation is verified under the viaIR default. These results
motivate keeping the two libraries side by side before migrating consumers.

## Shared primitives and unpacking

The implementation shares header validation (`payloadLength`, `fixedLength`),
full-width end arithmetic (`endAt`), containment (`boundedEnd`), and cursor
construction (`pack`). These private helpers have explicit preconditions:
lengths fit uint32, and packing follows a successful containment or exactness
proof. Consumers never need to repeat those proofs.

- `take` composes header validation, containment, and packing.
- `enter` reuses `take` and adds 8 without another check.
- Prefix entry passes the decoded length to `payload`, avoiding reconstructing
  that length from an intermediate cursor. It checks containment, then prefix
  length, once each.
- `unpackExact` uses end equality as its containment proof.
- `unpack64` validates an exact header and containment, then loads the two
  proven fields and returns the advanced source cursor.
- `unpackBalance` uses the same fixed-header validation and bounded advancement
  primitives, then loads the asset and unsigned amount.

```solidity
(bytes32 asset, uint amount, uint nextCur) = CursorBlocks.unpackBalance(streamCur);
streamCur = nextCur;
```

`unpack64` takes a key rather than a specification because its payload width is
intrinsically 64 bytes. All validation stays observable even when a caller
ignores the returned cursor; correctness tests exercise that case.

Measured incremental gas per block under Solidity 0.8.35, viaIR, optimizer 200,
and Cancun:

| Operation | Existing bounded pattern | Fused reference | Shared primitives |
|---|---:|---:|---:|
| Exact/ranged schema selection | 320 | 246 | 246 |
| Unbounded schema selection | 298 | 246 | 246 |
| Key selection | 189 | 207 | 207 |
| Fixed-header selection | 174 | 195 | 195 |
| Generic selection | 220 | 179 | 179 |
| Payload entry | 323 | 249 | 249 |
| Payload entry after 16 bytes | 418 | 271 | 271 |
| Generic two-word unpack | 280 | 189 | 189 |
| BALANCE unpack | 189 | 189 | 189 |

Unpack loops use 64-byte payloads. When the returned block cursor is discarded,
both the fused and shared versions cost 165 gas per block. Their complete test
harness runtime sizes also match: 984 bytes for generic unpack and 967 bytes
for BALANCE unpack. These sizes include external test methods, not just helpers.
Baseline unpack adapters construct cursors to give consumers equivalent results;
the measurements are not production endpoint transaction costs.

The simpler shared implementation therefore has no measured gas penalty in
these consumers. This does not establish universal optimality: key and fixed
selection still cost more than their existing bounded baselines, and compiler
inlining and caller shape can change results.

`FusedCursorBlocks` freezes the previous duplicated implementation for direct
comparison. `PreviousCursorBlocks` retains the initial entry/prefix layering.
Entry through `take + 8` ties fused entry under viaIR; retaining decoded length
for prefix entry saves 21 gas compared with that initial layering. Deriving a
fixed block's end from the validated expected header saves 6 gas under viaIR.
The unpack benchmark also retains composed `takeFixed`, end-only, and direct
assembly candidates. Raw results, compiler settings, and runtime sizes go to
`.npm-cache/cursor-unpack-results-ir.json`.

## Dynamic STEP unpacking

`unpackStep` returns `(uint cmd, uint value, uint inputCur, uint nextCur)`.
The child cursor covers only the nested BYTES payload; `nextCur` retains the
source boundary and metadata. Consumers assign it directly without rechecking.

```solidity
(uint cmd, uint value, uint inputCur, uint nextCur) = CursorBlocks.unpackStep(streamCur);
streamCur = nextCur;
bytes calldata input = Cursors.raw(inputCur);
```

The implementation reuses `payloadLength` and `advance` to establish the
parent end, available as `uint32(nextCur)`. A private `tail(abs, endAbs, key)` primitive derives the expected
child length from that known end and compares the entire key/length header.
Checking that the child body does not pass the parent end prevents
subtraction underflow and proves that the fixed prefix and child header fit,
without separate checks for each. Since the parent end already fits uint32,
the derived child length does too. Fixed-word loads happen after validation. Computing the child offset
uses unchecked uint256 arithmetic on a uint32 position, which cannot overflow;
the offset remains full-width until the tail proof succeeds.

The parent key is checked before its logical bound, then the child shape.
Containment failures use `OutOfBounds`; wrong keys, short prefixes, malformed
children, and trailing bytes within the parent use `InvalidBlock`. The old
`Blocks` adapter validates the child before its caller checks the parent bound,
so error precedence differs when both are invalid. The new tests specify the
new order explicitly. The caller still establishes calldata provenance.

Comparison under the default Solidity 0.8.35/viaIR/200-runs/Cancun build:

| Implementation | Cursor consumer gas/block | Calldata/hash consumer delta vs baseline | Harness runtime bytes |
|---|---:|---:|---:|
| Existing `Blocks.unpackStep` with caller containment | 446 | 0 | 1148 |
| `enter(cur, Step, 64)` then `exact(child, Bytes spec)` | 396 | 0 | 1478 |
| `take(cur, Step)` then expected tail header | 384 | -15 | 1480 |
| Fused reference | 334 | -62 | 1374 |
| Shared end/tail primitives (selected) | 334 | -62 | 1366 |

The calldata baseline consumes the original returned slice directly; it does
not round-trip through a cursor. Cursor consumers compare fixed words and
payload length while advancing the stream. Calldata consumers additionally
hash every payload. Hashing includes copying and memory expansion, so its
absolute per-block cost is not constant; the table reports the incremental
difference between equivalent consumers. The selected implementation matches
the fused reference's measured total gas at every tested size in both modes.

Streams contain 1, 32, or 128 blocks with 0-, 1-, 33-, or 256-byte payloads.
All measurements include loop work, exclude transaction intrinsic gas, and
are consumer-specific. Runtime sizes include all harness methods, not just the
unpacker. The shared structure matches the fastest tested candidate; it is
not a claim of a universal gas minimum. The initial shared version retained a
checked child-offset addition, costing 34 more gas per block in these loops;
removing that unnecessary overflow check closed the gap to fused assembly.
Using the known uint32 parent end also lets the tail primitive check underflow
directly instead of comparing its derived length to uint32.max. Gas is unchanged,
and the complete harness is eight bytes smaller than the fused reference.

Correctness tests cover full-width fixed values, unaligned starts, empty and
large payloads, logical truncation despite valid trailing calldata, reversed
ranges, short fixed prefixes, partial child headers, wrong keys, mismatched
child lengths, extra children, and callers that discard the payload cursor.
The candidate implementations are retained in `TestCursorDynamic.sol`.

```sh
npm test -- test/cursor-dynamic.test.ts
npm run bench -- test/cursor-dynamic.bench.test.ts
```

Raw measurements and compiler settings are written to the ignored
`.npm-cache/cursor-dynamic-results.json`.

## Sibling children and wider fixed blocks

RELAY contains INPUT and BYTES children. CONTEXT contains an account word
followed by STATE and INPUT children. Their unpackers return separate payload cursors followed by the
advanced source cursor, consistently with fixed-field and STEP unpackers.

```solidity
(uint inputCur, uint stepsCur, uint nextCur) = CursorBlocks.unpackRelay(streamCur);
(bytes32 account, uint stateCur, uint contextInputCur, uint nextContextCur) = CursorBlocks.unpackContext(streamCur);
```

The shared `pair(abs, endAbs, key)` primitive reads the first header and keeps
its derived next position full-width. It then calls `tail(nextAbs, endAbs, key)`.
A successful tail proof establishes that the second child's header fits and
its payload consumes the parent's remainder exactly. Since the first child
ends at that header, the same proof bounds the first child and any preceding
fixed prefix. Packing happens only after this proof. A separate first-child
containment check is redundant in this specific two-child structure.

`lengthAt(abs, key)` shares the key/header read while accepting full-width
positions; the cursor-based `payloadLength` delegates to it after extracting
the position. The private `pack(abs, endAbs)` now takes already validated
absolute positions and performs no masking. Public cursor entry points extract
their uint32 positions before calling it. This avoids repeating a mask on
positions already proven by the tail check, while preserving clean outputs.
Both primitives have explicit NatSpec preconditions.

All malformed child structures use InvalidBlock, including a first child
extending beyond the parent. Outer containment still uses OutOfBounds and is
checked first. The retained composition through independent `enter` calls
uses OutOfBounds for an oversized intermediate child instead; correctness
tests explicitly account for this difference. No returned cursor may escape
its parent, including when intermediate arithmetic crosses uint32.max.

Default viaIR measurements, incremental gas per block for cursor consumers:

| Structure | RELAY | CONTEXT | Five-word unpack |
|---|---:|---:|---:|
| Existing bounded Blocks adapter | 581 | 616 | 352 |
| Composition through packed helpers | 682 | 714 | 346 |
| Fused reference with separate first-child bound | 522 | 529 | n/a |
| Fused reference | 500 | 507 | 346 |
| Selected shared primitives | 473 | 491 | 234 |

The separate intermediate bound costs 22 gas in the fused reference. Removing
the unnecessary mask in the shared packer saves another 21 gas for RELAY and
9 for CONTEXT in these cursor loops. Compiler inlining and surrounding code
account for differences beyond the direct operation count: fused source is
not automatically the fastest generated code.

For callers hashing both calldata payloads, the selected RELAY helper saves
7 gas/block and CONTEXT saves 30 versus native calldata-returning bounded
Blocks adapters. These comparisons include conversion of the new cursors to
calldata views. Absolute hash costs vary with payload length and memory growth.
Sibling payload-size pairs are (0,0), (0,33), (33,0), (1,31), and (33,256), with
1, 32, and 128 parents. Decoded outputs and final stream metadata are compared
before recording gas. The table is a loop slope, not a guarantee for every
isolated call: a single CONTEXT cursor call costs 8 more gas than the fused
reference in this harness, despite the better multi-block slope. A single
RELAY calldata/hash call costs 17 more gas than its Blocks baseline, while the
multi-block slope saves 7 gas per block.

Five-word unpacking follows the existing `unpack64` structure: validate the
exact header and end once, load the words, then pack the returned range.
When its cursor is discarded it costs 219 gas/block, versus 333 for the
bounded Blocks adapter and 327 for the fused candidate.

The selected implementations trade code size for lower runtime gas in these
harnesses. Full harness runtime sizes are 1504 bytes for RELAY (1276 baseline),
1525 for CONTEXT (1288 baseline), and 908 for five-word unpacking (829 baseline).
These include multiple external test methods; they are not isolated helper
sizes or production contract deployment costs.

Correctness coverage includes empty and unequal siblings, unaligned starts,
full-width fixed values, parent truncation with valid trailing calldata,
reversed ranges, missing headers, wrong child keys, extra siblings, short
fixed prefixes, oversized first-child lengths (including uint32.max), and
callers discarding decoded ranges. All earlier cursor tests and benchmarks
are rerun when changing shared primitives.

```sh
npm test -- test/cursor-siblings.test.ts test/cursor-wide.test.ts
npm run bench -- test/cursor-siblings.bench.test.ts test/cursor-wide.bench.test.ts
```

Raw results are written to `.npm-cache/cursor-siblings-results.json` and
`.npm-cache/cursor-wide-results.json`, including compiler settings and every
measured stream size. Original Blocks remains unchanged by this experiment.

## Position-constraint expectations

```solidity
streamCur = CursorBlocks.expectPositionConstraints(streamCur, position);
```

The helper validates one 136-byte POSITION_CONSTRAINTS block and compares its
four fields directly against the supplied memory position. It returns the
advanced source cursor, preserving the source end and metadata, consistently
with unpackers. It does not allocate a constraints struct, modify the position,
or check its counterparty. The caller assigns the returned cursor to its stream.
The minimum receipt and maximum debt are inclusive full-width uint256 values.
A zero maximum debt means exactly zero, not an unbounded maximum.

The advancing API measures 339 gas/block when its return is used and 350 when
discarded in the current complete harness (Solidity 0.8.35, viaIR, optimizer 200,
Cancun). Runtime size is 1620 bytes, including the new metadata inspection entry
point. The focused tests cover exact exhaustion, trailing blocks, all metadata
bits, unchanged position fields, error precedence, and discarded returns.

The shared primitives are:

- `fixedLength(cur, header)` and `advance(cur, 8 + len)`: exact header validation
  and full-block containment, once each, returning the advanced source cursor.
  Fixed unpackers use the same composition.
- `read32(abs)`: an internal, unchecked absolute calldata load, also available
  to consuming libraries. It takes a full-width absolute position, not a cursor,
  and does not repeat schema or bounds checks. Reads past calldata use EVM
  zero-padding. Callers establish any required logical bounds themselves.
- `either(a, b)`: eager OR of two predicates. Unlike Solidity `||`, both
  arguments are evaluated before the call. It is used only with safe reads
  of fields already proven to fit, and removes short-circuit branches.
- `advance` adds the validated byte count without carrying into the source
  end or metadata lanes; consumers need no additional bounds check.

Identifiers are checked before quantities. Header mismatch reverts
InvalidBlock; a correct header outside the source range reverts OutOfBounds;
identifier mismatch reverts UnexpectedValue; quantity failure reverts
OutOfRange. The existing bounded Blocks adapter checks its source range before
calling Blocks, so malformed-and-truncated input has different error precedence.
The comparison tests specify these differences rather than hiding them.

Historical range-returning API measurements under viaIR, incremental gas per
successful block (the advancing API is measured separately below):

| Structure | Returned cursor used | Cursor discarded | Harness runtime bytes |
|---|---:|---:|---:|
| Bounded `Blocks.expectPositionConstraints` adapter | 400 | 387 | 1460 |
| Readable word loads with short-circuit `||` | 432 | 419 | 1471 |
| `takeFixed` then short-circuit comparisons | 449 | 436 | 1477 |
| Grouped assembly comparisons after shared end validation | 372 | 359 | 1447 |
| Fully fused reference | 372 | 359 | 1443 |
| Frozen read-then-compare primitives with eager OR | 366 | 353 | 1445 |
| Selected comparison primitives with eager OR | 363 | 350 | 1444 |

The selected version saves 37 gas/block over the bounded Blocks adapter and
69 over the initial readable implementation. It improves on the frozen eager-OR
read-then-compare version by 3 gas/block. Decoding to a memory constraints
struct before comparing costs about 612 gas/block with the return cursor used
in the 1-to-128-block slope; allocation makes that candidate's cost nonlinear.
Equality, improved outcomes, zero bounds, and full-width bounds are measured
at stream sizes 1, 32, and 128. Outputs and stream metadata are checked before
recording gas. Runtime sizes include all harness entry points, not just the
helper, and the gas numbers include consumer loop work.

Failure-path measurements use a caught external staticcall and include that
harness overhead. The selected helper costs 1134 gas for either identifier
mismatch and 1207 for either quantity failure, versus 1231/1244 for the Blocks
adapter. Short-circuiting still has a tradeoff: the initial readable candidate
fails on its first identifier at 1124 gas, 10 less than the selected eager
version. The selected implementation favors successful checks while preserving
all required error priorities.

Tests cover exact boundaries, uint128 crossings and uint256 extremes, either
identifier mismatch combined with quantity errors, literal zero maximum debt,
unaligned offsets, reversed ranges, logical truncation despite valid trailing
calldata, wrong keys and sizes, unchanged position/counterparty values, clean
returned cursors, and validation when the cursor is discarded. A deterministic
mixed-case sweep compares results with independent predicates.

```sh
npm test -- test/cursor-expect.test.ts
npm run bench -- test/cursor-expect.bench.test.ts
```

Candidates remain in `TestCursorExpect.sol`; raw settings, gas measurements,
and failure-path results go to `.npm-cache/cursor-expect-results.json`.
Experimental verification runs focused cursor suites and benchmarks; full
repository verification is reserved for integration checkpoints.

## Unchecked comparison helpers

All comparison helpers are internal library functions, callable by consuming
libraries. They operate on full-width absolute calldata byte positions, never
packed cursors, and return booleans without reverting on a failed comparison.
The word at the first position is always the left operand.

| Supplied-value helper | Two-position helper | Test |
|---|---|---|
| `equal32(abs, bytes32 value)` | `equalAt32(abs, otherAbs)` | Left == right |
| `lt32(abs, uint value)` | `ltAt32(abs, otherAbs)` | Left < right |
| `le32(abs, uint value)` | `leAt32(abs, otherAbs)` | Left <= right |
| `gt32(abs, uint value)` | `gtAt32(abs, otherAbs)` | Left > right |
| `ge32(abs, uint value)` | `geAt32(abs, otherAbs)` | Left >= right |

Ordering is unsigned across all 256 bits. Reads may be unaligned, overlap, or
use the same position. No bounds or schema checks are added; EVM zero-padding
applies beyond calldata. Callers must establish any logical bounds they need.
These are predicates, unlike Blocks' read-and-expect comparison helpers that
revert on a failed comparison.

The primitives reuse `read32` and simple comparisons. Inclusive predicates reuse
strict ordering. For inequality, use `!equal32(abs, value)` or
`!equalAt32(abs, otherAbs)` directly. Two-position predicates compare the two raw
reads directly, rather than routing a read through the supplied-value overload;
that structure removes a measured 6-gas overhead in the combined-predicate loop.
Under the default viaIR compiler, both final forms match explicit reads followed
by Solidity comparisons at every tested stream size. All six predicates together
cost 200 gas/iteration with a supplied value and 221 with two positions in the
comparison harness, including common loop and result-packing work. These are
not isolated opcode costs. Sizes 1, 32, and 128 cover equal, lesser, greater,
and high-bit unsigned operands.

POSITION_CONSTRAINTS uses predicates after its one-time shape/containment proof:

```solidity
if (either(!equal32(abs, position.asset), !equal32(abs + 64, position.liability)))
    revert UnexpectedValue();
if (either(gt32(abs + 32, position.amount), lt32(abs + 96, position.debt)))
    revert OutOfRange();
```

The operand order is deliberate: the declared minimum exceeds actual receipt,
or the declared maximum is below actual debt. The semantic helper still owns
error selection and priority. Its measured loop cost improves from 366 to 363
gas/block, or from 353 to 350 when the returned cursor is discarded. The frozen
prior helper remains in `ReadCompareCursorBlocks.sol` for regression comparison.

Tests cover all six predicates against independent unsigned comparisons, uint128
and uint255 boundaries, uint256.max, unaligned and overlapping positions, identical
positions, partial words, and full-width out-of-calldata positions that must not
be narrowed to uint32. Results are stored in `.npm-cache/cursor-comparisons-results.json`.

```sh
npm test -- test/cursor-comparisons.test.ts test/cursor-expect.test.ts
npm run bench -- test/cursor-comparisons.bench.test.ts test/cursor-expect.bench.test.ts
```

## Returning the advanced source cursor

Every `unpack...` helper now returns its decoded values followed by the advanced
source cursor. The experimental `...Next` names have been removed. The old
range-returning implementations live only in test-only `RangeCursorBlocks`;
`take` and `enter` remain the production APIs for selecting ranges.

```solidity
(bytes32 asset, uint amount, uint nextCur) = CursorBlocks.unpackBalance(cur);
cur = nextCur;

(uint cmd, uint value, uint inputCur, uint nextStepCur) = CursorBlocks.unpackStep(cur);
cur = nextStepCur;
```

In a consuming library, assignments can target its stream directly:

```solidity
(asset, amount, exec.decoders) = CursorBlocks.unpackBalance(exec.decoders);
```

`nextCur` preserves the original exclusive source end and every metadata bit;
only its low uint32 position becomes the consumed block's end. STEP's `inputCur`
is still a separate clean range over the BYTES payload. Pure helpers return
updated words rather than mutating the caller's state.

Most unpackers use `advance(cur, 8 + len)` inside `unchecked`, which validates
containment and returns the updated source cursor in one call. The helper requires
`size <= uint32.max + 8`; these lengths are uint32-derived, so both the caller
addition and the full-width position calculation are safe. It then adds the
byte count directly to the source cursor. Containment
proves that addition cannot carry into the source end or metadata lanes.
BALANCE now has a specialized fused implementation with the same validation and
advancement contract (see “Promoted BALANCE optimization” below). STEP supplies
`payloadLength` and uses the returned
position as the absolute end for `tail`. Trusted `read32` loads need no further
bounds checks. Range-selecting helpers retain `boundedEnd` because they need an
absolute end rather than an advanced source cursor.

The alternatives are retained in `TestCursorNext.sol`: caller-side advancement
from selected ranges, thin wrappers over the existing unpackers, direct fused
implementations, and the chosen implementations built from shared primitives.
The comparison includes realistic full harnesses and minimal loop-only consumers,
because surrounding methods materially affect viaIR inlining.

Initial direct-advancement measurements under Solidity 0.8.35, viaIR, optimizer
200, Cancun (before the `boundedNext` composition described below):

| Consumer | Caller advances from range | Returned advanced cursor | Delta/block |
|---|---:|---:|---:|
| BALANCE, next cursor used | 256 | 229 | -27 |
| BALANCE, returned cursor discarded | 237 | 237 | 0 |
| STEP, payload cursor used | 392 | 398 | +6 |
| STEP, payload hashed (33 bytes) | 653.323 | 647.323 | -6 |

The selected implementations match the direct fused references in these minimal
consumers. Minimal harness runtime sizes also fall: BALANCE from 545 to 530 bytes,
STEP from 737 to 726. Hashing has memory-expansion costs, so those absolute values
are rounded incremental slopes rather than constant isolated helper costs.

In the larger correctness/benchmark harnesses, BALANCE goes from 256 to 174
and STEP's cursor consumer from 392 to 328 gas/block. Their harness runtime
sizes grow from 877 to 933 and from 1165 to 1394 bytes respectively. These larger
savings should not be generalized to every consuming contract. The minimal
STEP cursor consumer demonstrates a real tradeoff from the extra return value.

A wrapper around the existing BALANCE unpacker costs 201 gas/block in the full
harness, compared with 174 for direct advancement from `fixedEnd`. For STEP,
the wrapper saves 3 gas versus the direct implementation in the full cursor
harness but loses 3 in its hash consumer. The minimal wrapper cursor loop costs
410 versus 398 for direct advancement. The direct implementations provide the
more consistent result across the tested consumers while retaining shared
validation primitives.

Benchmarks cover 1, 32, and 128 blocks, with STEP payload lengths 0, 1, 33, and
256. They verify decoded values and final stream words before measuring slopes.
Correctness tests cover empty child payloads, unaligned starts, trailing blocks,
exact source exhaustion, zero and all-set metadata lanes, malformed shapes,
logical truncation despite valid trailing calldata, reversed ranges, mixed-size
streams, and rejection even when callers discard cursor returns.

The library now chooses one consistent advancing contract for all unpackers.
The measurements retain the composite tradeoffs explicitly; consistency does
not imply every consuming loop becomes cheaper.

```sh
npm test -- test/cursor-next.test.ts
npm run bench -- test/cursor-next.bench.test.ts
```

Raw measurements, compiler settings, and harness sizes are written to
`.npm-cache/cursor-next-results.json`.

### Cursor-returning bounds primitive (historical, before advance)

The former `boundedNext` composition uses checked containment followed by
unchecked addition, rather than clearing and replacing the position lane:

```solidity
boundedEnd(cur, len);
unchecked { nextCur = cur + 8 + len; }
```

Minimal-loop results, compared with the initial direct-advancement implementation:

| Consumer | Direct end then advancement | `boundedNext` | Delta/block |
|---|---:|---:|---:|
| BALANCE, next cursor used | 229 | 220 | -9 |
| BALANCE, returned cursor discarded | 237 | 228 | -9 |
| STEP, payload cursor used | 398 | 404 | +6 |
| STEP, payload hashed (33 bytes) | 647.323 | 653.323 | +6 |

Current minimal runtime sizes are 524 bytes for BALANCE and 737 for STEP.
The full harness measures 159/165 gas per BALANCE block (cursor used/discarded)
and 342/654.323 per STEP block (cursor/hash), with runtime sizes 911/1421 bytes.
Historical selected-range and frozen candidate measurements remain unchanged.
The simpler primitive helps BALANCE, while STEP pays to recover an absolute
end from the returned cursor for child validation. This remains an experimental
API tradeoff, not a uniform performance improvement.

Making `boundedEnd` extract its result from `boundedNext` was also tested and
rejected: viaIR did not consistently eliminate the unnecessary cursor packing.
At that stage the retained dependency was `boundedNext` calling `boundedEnd`, so both return
contracts share one bounds check without penalizing existing range helpers.

## Uniform unpacker verification

Field-order experiments under the default viaIR settings found a measurable
benefit to child-first decoding in STEP and CONTEXT. STEP's full harness goes
from 398 to 401 gas/block when reading command/value before the tail, and its
minimal cursor/hash consumers also increase by 3. CONTEXT goes from 513 to 522
when loading account before its children. Expressing STEP's reads in a separate
assembly block gives the same result. The faster child-first order is retained
and documented in source. Fixed-width unpackers already load fields in wire
order. RELAY parses the first child's header before the second; it retains the
full-width end until the final-child proof succeeds, then packs the first range.
Moving that packing earlier showed no benefit and was not retained.

`cursor-uniform.test.ts` exercises all six current unpackers directly, checking
value order, clean child ranges, source metadata preservation, exact exhaustion,
trailing blocks, unaligned starts, malformed children, reversed logical ranges,
and rejection when callers discard cursor returns. `cursor-uniform.bench.test.ts`
measures complete consuming loops at 1, 32, and 128 blocks and verifies their
checksums and final cursors before reporting slopes. Its full harness includes
inspection methods; compare like-for-like consumers rather than treating those
slopes as isolated primitive costs. Raw results are in
`.npm-cache/cursor-uniform-results.json`.

With Solidity 0.8.35, viaIR, optimizer 200, Cancun, these full harness loops
measure 244 gas/block for `unpack64`, 316 for `unpack160`, 214 for BALANCE,
398 for STEP, 516 for RELAY, and 513 for CONTEXT. Dynamic cases use a 33-byte
final child; RELAY and CONTEXT have an empty first child. These results have
different surrounding methods from the minimal `cursor-next` comparison.

## Complete consumer flows

`TestCursorConsumers.sol` compares three matching workloads with independent
host-side expected results. Old consumers use `Blocks` and keep absolute
positions across the stream; new consumers use `CursorBlocks` and pass cursors
directly between helpers. Old consumers perform their required logical bounds
checks. New consumers trust the checks inside `CursorBlocks` without repeating
them. This compares the natural representations of both implementations, not
an old implementation forced to reconstruct packed cursors every iteration.

- Envelope: select a BYTES envelope by key, then decode its BALANCE children.
  The new path passes the selected range into the child consumer after skipping
  the already validated eight-byte header. It extracts only the envelope end
  needed to resume the outer stream; it does not split the range for decoding.
- STEP: unpack command/value and pass its input cursor directly to the BALANCE
  child consumer. The old path consumes the calldata view returned by `Blocks`.
- Chain: unpack BALANCE, then check POSITION_CONSTRAINTS using the returned
  cursor. Both sides use the same memory position and constraints.

Solidity 0.8.35, viaIR, optimizer 200, Cancun. Incremental gas per complete outer
envelope/STEP or BALANCE+constraints pair, including child decoding:

| Flow | BALANCE children | Blocks | CursorBlocks | Difference |
|---|---:|---:|---:|---:|
| Envelope | 0 | 184 | 291 | +107 |
| Envelope | 1 | 338 | 521 | +183 |
| Envelope | 4 | 800 | 1211 | +411 |
| Envelope | 16 | 2648 | 3971 | +1323 |
| STEP | 0 | 416 | 416 | 0 |
| STEP | 1 | 576 | 593 | +17 |
| STEP | 4 | 1056 | 1124 | +68 |
| STEP | 16 | 2976 | 3248 | +272 |
| BALANCE + constraints | — | 496 | 627 | +131 |

Runtime sizes (old/new): envelope 524/587 bytes, STEP 609/618, chain 766/765.
The benchmarks exclude common source/position setup and the old path's single
final conversion for comparing stream state. Counts 1, 32 and 128 verify linear
slopes; no memory expansion occurs inside these measured loops. Child counts
0, 1, 4 and 16 distinguish outer overhead from child decoding cost.

These measurements do not support assuming that cursor handoff alone removes
the earlier key-selection penalty. In this harness the new BALANCE child loop
adds 76 gas/child in the envelope flow but 17 in the STEP flow. This sensitivity
to surrounding code is consistent with compiler inlining/stack-allocation
effects; no opcode-level attribution has been established. Optimize against
these complete consumers and retain them as controls, rather than treating a
single primitive benchmark as a universal cost.

`cursor-consumers.test.ts` verifies checksums, counts, exact source exhaustion,
all metadata bits, unaligned starts, empty children, logical truncation with
physical trailing bytes, and malformed nested fields. The two implementations
need not have identical revert precedence on malformed input; both must reject.
`cursor-consumers.bench.test.ts` verifies values and final cursors against the
host-side oracle before reporting gas. Raw data and compiler settings are in
`.npm-cache/cursor-consumers-results.json`.

## Consumer optimization experiments (test-only)

`CursorConsumerCandidates.sol` and `TestCursorConsumerCandidates.sol` contain
experimental primitives and consumer variants. The measurements in this section
were recorded before promotion, with production `CursorBlocks` unchanged.
The candidates retain bounded cursor inputs, advancing cursor
returns, metadata preservation, and the required validation. No candidate
turns fixed-field unpacking into unchecked input acceptance.

Measured gas per outer operation, default Solidity 0.8.35/viaIR/200/Cancun:

| Candidate | Envelope, 4 children | STEP, 4 children | BALANCE + constraints |
|---|---:|---:|---:|
| Existing Blocks consumer | 800 | 1056 | 496 |
| Current cursor consumer | 1211 | 1124 | 627 |
| Cache exclusive loop end | 1191 | 1145 | 615 |
| Shared absolute-position validation | 1007 | 1124 | 531 |
| Fused fixed-field helpers | 1007 | 1124 | 435 |
| Shared validation + cached end | 1027 | 1145 | 519 |
| Reduced-argument shared validation | 1007 | 1124 | 559 |
| Compare against exhausted cursor | 1160 | 1123 | 637 |
| Fused helpers + exhausted cursor | 996 | 1123 | 451 |

The isolated chain controls are especially useful: replacing only BALANCE
with the fused test helper measures **429**, retaining the production constraint
helper. Replacing only the constraint helper measures **435**. Replacing both
also measures 435. Thus helper costs are not additive: changing one helper can
change how the compiler optimizes the entire caller. These are measured whole
consumer outcomes, not proof that each changed instruction accounts for the
same saving in another contract. Exact opcode-level attribution remains open.

The shared absolute-position candidate extracts `abs` once, validates its header
and end in `fixedAt`, then reads fields and advances the original cursor. It
matches the fused reference in envelope and STEP consumers, supporting a small
shared primitive over blanket assembly duplication where the measurements agree.
The chain result still favors a specialized fixed-field implementation.

The exhausted-cursor loop compares the entire current word to a precomputed
word with position equal to end, preserving metadata in that terminal word.
This is a **consumer-specific** option: these consumers establish valid initial
ranges and use advancing helpers that cannot overshoot. It is not a generic
replacement for a bounded-loop check on arbitrary/reversed cursors.

Tradeoffs across workload sizes:

- Shared absolute primitives: envelope cost changes from `291 + 230*n` to
  `299 + 177*n` gas for n BALANCE children. Empty envelopes regress by 8 gas,
  while larger ones improve. Harness size falls from 587 to 561 bytes.
- Fused helpers with exhausted-cursor comparison: envelope cost is
  `284 + 178*n`. This wins at four children (996), but loses by 1 gas to shared
  primitives at sixteen children (3132 vs 3131). Runtime is 595 bytes.
- STEP's exhausted-cursor variant goes from `416 + 177*n` to `411 + 178*n`.
  It saves only 1 gas at four children, loses 11 at sixteen, and grows the
  harness from 618 to 654 bytes. It is not a general improvement.
- The BALANCE-only chain candidate saves 198 gas and shrinks the harness from
  765 to 718 bytes. It is the strongest narrow candidate to investigate next.
- Manually moving the child loop into its caller changes neither gas nor size.
  Using `enter` instead of `take` plus eight costs 11 more gas per envelope in
  this harness. Neither source-level simplification is a measured improvement.

The experiment benchmark checks 1/32/128 outer operations with 0/1/4/16 children
and records runtime sizes. The correctness suite covers every candidate with
independent checksums, final cursor checks, metadata, offsets, truncation,
malformed nested fields, full-width constraints, and identifier-before-quantity
errors. Run `test/cursor-consumers.test.ts` and
`test/cursor-consumer-candidates.bench.test.ts`; raw results are in
`.npm-cache/cursor-consumer-candidates-results.json`.

## Promoted BALANCE optimization

The production library now uses the measured specialized `unpackBalance` body:
extract the position once, compare the exact header, check the full-width block
end once, load the two fields, and advance by 72. The cursor API, header-before-
bounds error order, metadata, source boundary, and validation guarantees are
unchanged. The expectation helper and consumer loops remain unchanged.

The direct key-selection candidate was also tried in production. It did not
improve any measured selection or consumer result over the existing shared
`take(cur, key)` implementation, so the shared implementation was retained.

Final complete-consumer results under the same compiler settings:

| Flow | Before | After | Old Blocks |
|---|---:|---:|---:|
| Empty envelope | 291 | 299 | 184 |
| Envelope, 1 BALANCE | 521 | 476 | 338 |
| Envelope, 4 BALANCEs | 1211 | 1007 | 800 |
| Envelope, 16 BALANCEs | 3971 | 3131 | 2648 |
| STEP, 4 BALANCEs | 1124 | 1124 | 1056 |
| BALANCE + constraints | 627 | 429 | 496 |

Envelope harness size falls from 587 to 561 bytes; chain size falls from 765 to
718. STEP remains 618 bytes. Empty envelopes regress by 8 gas, a caller/compiler
tradeoff retained for the larger decoding savings. Standalone selection and
`cursor-next` benchmark slopes and runtime sizes were unchanged after promotion.
This improvement is visible in complete consumers even when isolated helper
measurements are identical. Current raw consumer data remains in
`.npm-cache/cursor-consumers-results.json`; earlier sections retain explicitly
historical measurements for comparison.

## Absolute decoders with thin cursor wrappers (test-only)

`CursorAbsoluteWrappers.sol` tests private absolute-position decoders underneath
the same packed-cursor API. The absolute primitives validate and decode; the
wrappers extract cursor lanes, advance fixed blocks by their known sizes, or
pack dynamic child ranges and replace the source position. Validation is not
repeated. Production `CursorBlocks` was unchanged during this experiment.

The exact BALANCE structure tested is:

```solidity
(asset, amount) = unpackBalanceAt(uint32(cur), uint32(cur >> 32));
unchecked { nextCur = cur + 72; }
```

The private `unpackBalanceAt` checks the exact header and full block containment
before reading either field. An absolute expectation primitive similarly owns
header, bounds, identifiers, and quantity checks; its wrapper advances by 136.
The dynamic STEP primitive returns command, value, input position, and parent
end as absolute values. Its wrapper creates the child cursor and updated source.

Complete consumers, Solidity 0.8.35/viaIR/200/Cancun:

| Conversion | Envelope, 4 children | STEP, 4 children | BALANCE + constraints |
|---|---:|---:|---:|
| Current production helpers | 1007 | 1124 | 429 |
| Only BALANCE uses an absolute primitive | 1007 | 1124 | 429 |
| BALANCE and expectation use absolute primitives | 1007 | 1124 | 432 |
| BALANCE, expectation, key selection, and STEP converted | 1007 | 1127 | 432 |

BALANCE's wrapper matches both gas and harness size in every measured consumer.
Key selection's absolute primitive also introduces no measured change in the
envelope flow. STEP adds 3 gas per parent at every tested child count, while its
harness shrinks from 618 to 610 bytes. The expectation conversion adds 3 gas per
chain and keeps its 718-byte harness size. These findings support absolute
primitives for organization, but do not establish a blanket performance win or
guarantee free wrappers for untested helpers/callers.

`TestCursorWrappers.sol` retains all three conversion scopes. The benchmark
`cursor-wrappers.bench.test.ts` checks 1/32/128 outer operations and 0/1/4/16
children; results are in `.npm-cache/cursor-wrapper-results.json`. The existing
consumer and advanced-return correctness suites also exercise these candidates,
including metadata, reversed ranges, truncation, malformed child headers,
discarded returns, and full-width constraint/error behavior.

## Further investigation of the envelope gap (test-only)

The production four-child envelope gap is `1007 - 800 = 207`, decomposed from
0/1/4/16-child measurements as **115 gas of parent overhead + 23 per BALANCE**.
The absolute consumer costs `184 + 154*n`; the production cursor consumer costs
`299 + 177*n`. It is therefore misleading to attribute all 207 gas to four
BALANCE decodes.

Optimized IR for both envelope contracts confirms that the selection and child
decoding helpers are inlined in this consumer. The cursor path still extracts
positions and limits in loops, constructs selected ranges, and preserves packed
source state. The absolute path retains separate positions and limits. Stack
scheduling also differs; the IR inspection does not attribute an exact gas
amount to each instruction. The remaining difference here cannot simply be
explained as calls that the compiler forgot to inline.

`CursorFurtherCandidates.sol` and `TestCursorFurther.sol` retain these additional
experiments. Production `CursorBlocks` remains unchanged:

| Candidate | Envelope, 4 children | STEP, 4 children | Chain |
|---|---:|---:|---:|
| Current cursor helpers | 1007 | 1124 | 429 |
| Whole-word less-than against exhausted cursor | 996 | 1123 | 445 |
| Omit redundant end mask in clean child loop only | 1001 | 1118 | 429 |
| Repack next cursor instead of adding fixed size | 1055 | 1172 | 429 |
| Load BALANCE words before validation | 1007 | 1124 | 429 |
| Signed remaining-space bounds check | 1019 | 1136 | 432 |
| Absolute positions inside child loop | 923 | 1037 | — |
| Fused BYTES unpacker returning payload/next cursors | 988 | — | — |
| BYTES unpacker composed from existing enter | 1003 | — | — |
| Advance parent before consuming children | 1003 | — | — |
| Return exhausted child cursor to parent | 1007 | — | — |
| Fused BYTES unpacker + absolute child loop | **911** | — | — |

The hybrid child consumer still accepts `uint cur`. It extracts `abs` and `end`
once and calls a bounds-validating absolute BALANCE primitive inside its loop.
Both a values-only primitive and a primitive returning the advanced absolute
position produce the same measured gas and harness size. This differs from the
previous thin-wrapper experiment, which still called a packed-cursor wrapper
for every child. Adopting the hybrid approach requires an absolute primitive
available to that consumer (or moving its loop into the primitive's library),
not merely reorganizing private functions underneath an unchanged per-child
cursor loop.

The fused BYTES candidate follows the unpacker convention: return a clean
payload cursor and the advanced source cursor, with one key and containment
check. It removes selected-range reconstruction from the parent consumer. The
combined envelope harness falls from 561 to 545 runtime bytes; hybrid STEP
falls from 618 to 609. These are measured consumer improvements, not a promise
of equal gains for arbitrary applications.

Hybrid STEP costs `385 + 163*n`, versus old Blocks at `416 + 160*n`: it wins
with four children (1037 vs 1056) but loses with sixteen (2993 vs 2976). The
combined envelope remains slower than old Blocks at four children (911 vs 800).
The packed-loop candidates require proven valid ranges and preserved high lanes;
the clean-child variant additionally requires zero metadata. Neither is a
drop-in condition for every possible source cursor.

`cursor-further.bench.test.ts` checks complete decoded results, final state and
linear slopes at 1/32/128 outer operations with 0/1/4/16 children. The consumer
correctness suite covers all variants, including malformed fields, truncation,
unaligned starts, metadata and quantity/error behavior. Results are in
`.npm-cache/cursor-further-results.json`. Optimized IR used for inspection is
saved as `.npm-cache/CursorConsumerEnvelopeOld.ir` and
`.npm-cache/CursorConsumerEnvelopeNew.ir`.

## Packed cursor command flow

`contracts/test/TestCursorCommandFlow.sol` and
`test/cursor-command-flow.bench.test.ts` compare the same consumer with old
Blocks adapters versus production CursorBlocks. Both retain packed cursors in
every loop and pass each updated cursor into the next helper. There are no
absolute-position child loops. Old adapters supply the logical bounds checks
and cursor advancement that Blocks delegates to callers; the new adapters
delegate directly to CursorBlocks without repeating its checks.

An outer STEP stream dispatches alternating command IDs. Each command loops
through records containing BALANCE, POSITION_CONSTRAINTS, then another BALANCE.
The first balance populates a reusable Position, the expectation validates it,
and both balances contribute to command-specific arithmetic. All decoded values
are checked against a separate TypeScript oracle using varied inputs. This is
a representative decoding and internal dispatch workload, not a full Execution
integration: no storage, external command calls, or transaction intrinsic gas
is measured. Source cursor setup and Position allocation are outside the timer.

Solc 0.8.35, viaIR, optimizer 200, Cancun; total measured gas for 16 commands:

| Records per command | Old Blocks, packed consumer | CursorBlocks | Difference |
| --- | ---: | ---: | ---: |
| 0 | 8,828 | 8,772 | -56 |
| 1 | 21,692 | 19,188 | -2,504 |
| 4 | 60,284 | 50,436 | -9,848 |
| 16 | 214,652 | 175,428 | -39,224 |

Runtime size is 951 bytes old and 976 bytes new. The benchmark also covers 2
and 64 commands and writes compiler settings, sizes, and raw measurements to
`.npm-cache/cursor-command-flow-results.json`. These results compare packed
consumers on both sides; earlier absolute-loop results answer a different question.
The regular focused tests cover empty streams/inputs, unaligned starts, metadata,
logical truncation despite trailing physical calldata, missing/malformed chained
fields, failing constraints, child boundaries, and unsupported commands.

Run with `npm run bench -- test/cursor-command-flow.bench.test.ts` and
`npm test -- test/cursor-command-flow.test.ts`.

### Experiment: advance by an explicit byte count

Isolated copies in `.npm-cache/cursor-blocks-ir/Advance*Blocks.sol` replace
`boundedNext(cur, len)` with `advance(cur, 8 + len)` at all six call sites.
Production libraries are unchanged. Same compiler and packed command consumer:

| Variant | Gas, 16 commands × 4 records | Runtime bytes |
| --- | ---: | ---: |
| Current boundedNext | 50,436 | 976 |
| Advance, checked caller addition | 54,391 | 1,150 |
| Advance, unchecked caller addition, bounded size | 49,332 | 972 |
| Advance, unchecked caller addition, arbitrary uint size | 50,532 | 977 |

The bounded-size advance compares full-width `position + size` with the source
end, then adds size to cur. Its precondition is `size <= uint32.max + 8`, matching
the existing block-length guarantee. It checks containment but is not safe for
arbitrary uint sizes that can overflow that absolute-position addition.
The unrestricted variant rejects `position > end` or `size > end - position`
using assembly and then advances; even uint256.max sizes cannot bypass it.
Both preserve the end and metadata on success. Caller `8 + len` can safely be
unchecked because these lengths are uint32-derived. viaIR did not eliminate
the cost of leaving that addition checked in this experiment.

The benchmark covers 2/16/64 commands and 0/1/4/16 records. Direct primitive
tests cover zero-size and exact-end advances, reversed ranges, exceeding the
end, uint32 lane carry, metadata, and (for the unrestricted helper) uint256
overflow attempts. All three copies also run the packed command correctness
suite. Results and experiment tests are saved under `.npm-cache/cursor-advance*`.

### Promoted advance primitive

`advance(cur, size)` now replaces `boundedNext` in CursorBlocks. It is internal
and advances by exactly size bytes, preserving the source end and metadata.
Its explicit precondition is `size <= uint32.max + 8`; it validates containment
but must not be passed arbitrary uint256 sizes. Each of the six unpack/expect
call sites adds the header inside unchecked arithmetic after obtaining a
uint32-derived payload length. Range helpers still use boundedEnd. BALANCE
retains its measured fused implementation.

The production packed command benchmark now measures 49,332 gas for 16 commands
with four records each (previously 50,436); runtime size is 972 bytes (previously
976). The preceding experiment and command-flow tables record pre-promotion
measurements. Direct advance tests cover empty ranges, partial and exact advances,
metadata, reversed ranges, and attempted position-lane carry. The focused run
passed 121 tests including the command benchmark; typecheck also passed.

### Shared absolute header validation

Fixed unpackers now extract `abs = uint32(cur)`, call
`expectHeader(abs, expected)`, then `advance(cur, 8 + knownPayloadSize)` before
reading fields. `expectHeader` validates only the eight-byte key/length header;
it does not prove containment. `fixedLength` also delegates its header check to
this primitive. BALANCE no longer needs its own fused header/bounds assembly.
Constant size additions need no unchecked scope; runtime uint32-derived lengths
still add their header inside unchecked arithmetic.

With the same viaIR settings, the 16-command/four-record packed flow decreased
from 49,332 to 48,551 gas, while runtime size increased from 972 to 980 bytes.
This change includes the shared fixedLength check, generic fixed unpackers,
BALANCE, and position constraints; it is not an isolated per-BALANCE saving.
The balance-only envelope remains 1,007 gas per four-child envelope. The combined
flow is 11,733 gas below its old Blocks packed-consumer baseline of 60,284.
The focused unpack/expect and command run passed 121 checks including two
benchmarks. Direct header tests separately verify unaligned positions, key and
length mismatches, and successful header-only validation without a payload.

### Uint headers

`contracts/codec/Headers.sol` defines all built-in header constants as uint values
derived from `Specs.<name> >> 192`. The right shift guarantees zero upper 192 bits
without a runtime mask. This is now the main Headers library, exported through
Codec.sol and Commands.sol; legacy uint64 constants remain only under test.

Blocks accepts uint headers in expectHeader, enterFixed, takeFixed, unpackFixed,
and expectRunFixed. Direct comparisons reject nonzero upper bits rather than
truncating them. Generic fixed unpackers construct uint headers too.

### Extract absolute positions once in composite unpackers

STEP, RELAY, and CONTEXT now start with `uint abs = uint32(cur)` and call
`lengthAt(abs, key)` directly. Subsequent field and child reads reuse abs, matching
the fixed unpackers. Cursor-based selection helpers retain their payloadLength
wrappers. This is a readability change: the viaIR comparison measured identical
per-block gas (STEP 398, RELAY 516, CONTEXT 513), identical runtime sizes, and
48,167 gas for the 16-command/four-record packed flow in both implementations.

### Consolidated absolute length readers

Both key and specification validation now use `lengthAt(abs, ...)` overloads
in the absolute-helper section. The cursor payloadLength wrappers were removed;
take, prefixed enter, and exact extract abs once and call lengthAt directly.
The focused selection tests and benchmark passed (77 checks). A separate frozen
pre-change consumer benchmark produced identical gas in every measured row and
identical per-block slopes. Executable bytecode was not identical in the combined
inspection harness, so this is measured gas parity, not a claim of identical
compiled code. No validation checks were removed.

### Further primitive consolidation

`endAt(abs, len)` now takes an absolute header position and sits with the absolute
helpers; it performs arithmetic only and does not need a cursor boundary.
The single-use fixedLength and fixedEnd forwarding helpers have been removed.
`takeFixed` extracts abs, validates with expectHeader, then selects the range
using boundedEnd and the expected header's low-32-bit payload length. Header
validation still happens before containment, and upper header bits still fail.
Earlier descriptions of fixedLength/fixedEnd above record the previous structure.

boundedEnd, advance, and payload remain cursor-based: they establish containment
using the source end, and advance also preserves metadata. Converting these to
abs alone would discard required information; passing separate bounds adds
arguments without removing that responsibility. No new raw-length wrapper was
added just to hide the one unvalidated header load in generic take.

### Complete fixed-header stream validation

`expectRunFixed(cur, expected)` sits beside runCountAt with the stream scan implementations.
It validates every remaining block against the supplied right-aligned uint header,
extracting abs/end and computing the stride once. Each iteration checks the fixed
block fits before calling expectHeader, preserving relay's per-block error order.
It reads no payload fields, returns nothing, and does not advance the caller's
cursor. Empty ranges pass; reversed ranges and truncated blocks fail OutOfBounds.
A complete block with a different header fails InvalidBlock. Callers establish
calldata provenance and supply an expected header with zero upper bits.

Executions.takeBalances now uses this validator and returns a clean payload
cursor for Relay to pass directly to Encoder.createContext. It preserves
undeclared-lane behavior and state metadata. See BlocksMigration.md for the
implemented caller benchmark, including source validation and consumption.

### Key/length header overload

The private `expectHeader(abs, key, len)` overload packs the expected header and
calls the existing uint-header validator. Its length must fit uint32. unpack64
and unpack160 now use this overload, avoiding repeated header-construction syntax.
The viaIR comparison measured identical gas and runtime size: 244/316 gas per
block respectively. Comparing key and length separately instead cost 24 extra
gas per block, so validation remains a single packed-header comparison.

### LIST unpacking

`(itemsCur, cur) = CursorBlocks.unpackList(cur)` validates the LIST header key
and complete container bounds, then returns a clean payload cursor plus the
advanced source cursor with its original end and metadata preserved. Empty
lists are valid. It composes lengthAt, advance, and pack without duplicate
checks. Items are not decoded or validated; consuming libraries iterate the
returned itemsCur and validate each item's expected shape themselves.

### Generic payload unpacking

`(payloadCur, cur) = CursorBlocks.unpack(cur, key)` selects a keyed payload and
advances the enclosing source. The uint spec overload additionally validates
minimum/maximum payload length (zero maximum is unbounded). Both check schema
before containment, preserve the enclosing end and metadata, and return a clean
payload cursor excluding the eight-byte header. Neither interprets payload
contents. unpackList now delegates to the key overload with Keys.List.

### Named payload wrappers

unpackBytes, unpackString, and unpackList are grouped directly after the generic
unpack overloads. All delegate to `unpack(cur, Keys.<kind>)`, returning a clean
payload cursor followed by the advanced source cursor. They add no repeated
validation. unpackString does not validate text encoding; unpackList does not
validate its items. Empty payloads are accepted by all three wrappers.

### Explicit header expectation names

The former lengthAt overloads are now expectKey(abs, key) and
expectSpec(abs, spec), grouped immediately after the expectHeader overloads.
expectKey validates the key; expectSpec also validates the declared length against
the specification. Both return the declared payload length and neither validates
containment. All CursorBlocks callers use these explicit names; earlier lengthAt
references above describe the previous naming. Validation logic is unchanged.

### Prefix entry returns the original body position

`(uint abs, uint payloadCur) = CursorBlocks.enter(cur, keyOrSpec, amount)` now
returns the original payload start plus a clean cursor beginning after the
validated prefix. The shared payload primitive computes both without repeated
bounds checks. Reads wholly within `[abs, abs + amount)` are proven in bounds;
the remaining payload is bounded by payloadCur. Zero-length prefixes and skipping
the whole payload are supported. The enclosing source cursor is not advanced.
The two-argument enter overloads still return only a payload cursor. Existing
comparison consumers explicitly discard abs where only the remainder is needed.

### Advancing selection verification

The selection benchmark now assigns nextCur from current take/takeFixed/unpack/
prefix-enter helpers directly, rather than reconstructing advancement from the
selected range. Frozen alternatives retain their old consumer convention. The
complete BYTES envelope consumer likewise uses take's returned source cursor;
its four-child workload decreased from 1,007 to 994 gas per envelope. The packed
command flow remains 48,167 gas for 16 commands with four records each.
The focused run passed 393 checks including three benchmarks, plus typecheck.
A fresh focused configuration at .npm-cache/cursor-api/config.ts uses updated
harness copies; older isolated experiment copies target historical signatures.

The single-use endAt primitive has since been removed. exact computes its
full-width end inline using unchecked addition of the uint32 position, header
size, and validated uint32 payload length, then checks exact end equality.

### Exact saved-constraint experiment (test-only)

An isolated candidate replaces expectPositionConstraints' advance with a single
full-width `abs + 136 == end` check and returns nothing. The same existing header
and value primitives remain. The benchmark builds saved cursor arrays before
timing, then validates 1/32/128 distinct unaligned constraint ranges; measurements
include the common array loop but exclude cursor setup and memory allocation.
With solc 0.8.35, viaIR, optimizer 200, Cancun:

| Validation | Gas per check | Harness runtime bytes |
| --- | ---: | ---: |
| Current helper, nextCur discarded | 333 | 969 |
| Current helper followed by next-position/end equality | 370 | 1,001 |
| Specialized exact-range helper | 333 | 969 |

All four value scenarios (equal, better, zero, full-width) give the same figures.
The specialized variant saves no gas over simply discarding the current return,
but enforces exactness for 37 gas less than the composed exact check. Trailing
bytes are accepted only by the discard variant. Truncation and identifier/quantity
failures were checked. The composed wrapper checks exactness after values; the
specialized variant checks it before values, so combined-invalid inputs can have
different error precedence. Production code is unchanged. Experiment sources,
bench test, compiler settings and results are under .npm-cache/exact-constraints*
and .npm-cache/cursor-api/{ExactConstraintBlocks,TestExactConstraints}.sol.

### Deferred value-only constraint checking (test-only)

A candidate expectPositionConstraintsAt(abs, position) contains only the existing
identifier and quantity checks, with abs pointing at an already-validated block
header. The checked cursor helper delegates its value checks to it after header
and containment validation. Production code remains unchanged.

The deferred benchmark builds saved cursors using takeFixed before the check
phase, so skipping validation has an established precondition. It tests distinct
unaligned blocks at 1/32/128 counts, equal/better/zero/full-width quantities, and
identifier/quantity failures. Invalid headers and truncated blocks fail during
initial selection. All variants use the same saved-cursor array loop.

| Deferred checker | Gas per check | Harness runtime bytes |
| --- | ---: | ---: |
| Current checked helper, return discarded | 333 | 1,045 |
| Checked helper sharing value-only primitive | 333 | 1,045 |
| Value-only absolute helper | 259 | 1,007 |

Value-only checks save 74 gas each in the isolated check phase. Including setup,
128 constraints measured 154,758 versus 144,887 gas (9,871 saved); those totals
include allocation/selection and compiler interactions and should not be inferred
by simply multiplying the isolated saving. Cursor setup and checking are timed
separately as well; an actual command hook is not simulated. The checked helper's
shared implementation also produced identical gas for every existing packed
command-flow benchmark row and identical 978-byte new-flow runtime size.
Artifacts and compiler settings are in .npm-cache/deferred-constraints-results.json
and .npm-cache/deferred-constraint-flow-results.json.

### Promoted payload-based deferred constraint checker

`checkPositionConstraints(abs, position)` now takes the absolute start of an
already-validated 128-byte POSITION_CONSTRAINTS payload, excluding its header.
It performs only identifier and quantity checks, preserving their error order.
Callers must establish the exact block header, containment, and calldata provenance
before saving the payload; unpackFixed supplies the first two checks:

```solidity
(constraintsCur, cur) = CursorBlocks.unpackFixed(cur, Headers.PositionConstraints);
// Run the command hook and obtain the resulting position.
CursorBlocks.checkPositionConstraints(uint32(constraintsCur), position);
```

The checked expectPositionConstraints validates the header and containment, then
passes abs + 8 to this same value-checking primitive. It still returns nextCur.
The saved payload remains a separate range; checking it does not advance a source.

With viaIR/optimizer 200/Cancun, deferred checking measures 253 gas per constraint
versus 333 for revalidating a saved full-block cursor: 80 gas saved. The checked
helper and every packed command benchmark row remain unchanged. Including cursor
setup and initial validation, 128 constraints measure 145,655 versus 154,758 gas,
saving 9,103. The earlier header-start unchecked candidate measured 144,887 total:
the payload convention saves 6 gas in the check phase but adds more setup work in
this harness. It is chosen for consistency with payload unpacking, not because it
beats the header-start candidate in total gas. These benchmarks simulate saved
ranges and later checking, not the hook execution itself.

The reproducible production comparison is test/cursor-deferred-constraints.bench.test.ts;
results and compiler settings are written to .npm-cache/cursor-deferred-constraints-results.json.

### Balance constraint checks

`cur = expectBalanceConstraints(cur, asset, amount)` validates a complete
BALANCE_CONSTRAINTS block (104 bytes), checks the asset and inclusive uint256
minimum/maximum amounts, and returns the advanced source cursor. It delegates
value checks to `checkBalanceConstraints(abs, asset, amount)`, where abs points
to the already-validated 96-byte payload, not its header. Save deferred payloads
using `unpackFixed(cur, Headers.BalanceConstraints)` just as for position
constraints. The payload checker does not establish header, bounds, or provenance.
Zero maximum is literal; inverted ranges cannot pass. Header errors precede
containment errors, which precede asset and then quantity errors.

### Separate Execution input and state cursors

Test-only layout candidates compare the existing five-word Execution struct
against a six-word struct with independent inputCur and stateCur fields. Both
use current CursorBlocks, packed position/end cursors, and write the returned
cursor back after every consuming call. The split candidate keeps each lane's
declared flag in bit 64 of that cursor. Production Execution is unchanged.

Solc 0.8.35, viaIR, optimizer 200, Cancun; gas for 16 iterations including
calldata cursor setup and Execution allocation:

| Flow | Combined decoders | Separate cursors | Separate minus combined |
| --- | ---: | ---: | ---: |
| Input balances | 5,130 | 5,169 | +39 |
| State balances | 6,617 | 5,216 | -1,401 |
| State balance and input constraint | 10,525 | 9,220 | -1,305 |
| Saved input constraint, state balance, deferred check | 11,846 | 10,535 | -1,311 |

The measured setup differential is +42 gas for separate cursors. Per-iteration
costs are unchanged for input-only processing (285 gas), fall from 375 to 285
for state-only processing, from 613 to 529 for mixed processing, and from 694
to 610 for deferred checking. Slopes agree across counts 1, 16, and 128, both
including and excluding setup. Harness runtime size falls from 1,368 to 1,309
bytes; this is not a prediction of production contract size.

The combined candidate shifts the state cursor out and merges it back while
preserving the input lane. Two alternative writes were also measured: replacing
only the state position lane adds 21 gas per state-consuming iteration, and
adding the shifted position delta adds 12. Neither improves the comparison.

These are internal gasleft measurements of representative loops, not complete
transaction gas or production command execution. Flags are preserved and tested,
but production declaration enforcement, open/close, external hooks, storage, and
output encoding are outside this experiment. The deferred hook is represented
by adding one to the decoded balance before checking its saved constraint.

Reproduce with test/execution-cursor-layout.bench.test.ts; correctness coverage
is in test/execution-cursor-layout.test.ts. Results, all four candidate sizes,
and compiler settings are written to .npm-cache/execution-cursor-layout-results.json.

### Execution layout adopted

Production Execution now uses independent `uint input` and `uint state` cursors
with the declared-lane flag in bit 64 of each. Opening, writer hint selection,
raw access, traversal, and finalization use the separate fields. Existing Blocks
unpackers and their validation behavior remain unchanged in this migration.
The layout benchmark now imports production Execution for the split candidate
and retains a frozen five-word struct for the combined baseline. Older helper
comparison harnesses use the new layout on both sides; their historical gas
figures describe the earlier layout and must not be treated as current results.

Rerunning the layout benchmark with production Execution reproduces every gas
row and runtime size above. Typechecking and the focused command-runner,
execution-helper, layout, and enter-loop benchmark/regression checks pass.

Regular verification completed with 1,892 passing tests and one obsolete
combined-field assertion in command-runner.test.ts. That assertion was updated
to verify both cursors across all four declaration combinations; the complete
three-test command-runner suite passed on its focused rerun. No behavioral
failures remained. A local config selected the cached native 0.8.35 compiler
with the default optimizer/viaIR/Cancun settings after Hardhat's compiler-list
lock timed out.

### Production balance command migration

`Executions.unpackBalance` now delegates directly:

```solidity
(asset, amount, exec.state) = CursorBlocks.unpackBalance(exec.state);
```

The cursor library owns header validation, containment, reads, and advancement;
Execution adds no duplicate checks. Other state and input unpackers retain their
existing implementations. BALANCE errors now follow CursorBlocks ordering:
invalid headers fail before containment. A correct header with a truncated
payload still fails OutOfBounds. Missing balances in paired loops now encounter
InvalidBlock where the old decoder reported OutOfBounds.

The permanent `test/command-balance-decoder.bench.test.ts` compares the actual
CheckBalance and Withdraw mixins against frozen command callbacks using the
previous balance decoder. Both use the same split Execution layout, runner,
constraint helpers, output writer, and host implementation. The withdrawal hook
records delivered amounts in storage; it does not model a token transfer.

Solc 0.8.35, viaIR, optimizer 200, Cancun target. Command execution measurements
wrap the real external entrypoint in CALL; the timer excludes construction of
that call's ABI input and transaction intrinsic/data charges, and includes CALL
and return copying. Transaction measurements use receipt gas from direct calls.

| Command | Balances | Previous execution | Cursor execution | Execution saved | Previous transaction | Cursor transaction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| checkBalance | 1 | 3,684 | 3,626 | 58 | 26,038 | 25,980 |
| checkBalance | 16 | 16,596 | 15,713 | 883 | 58,460 | 58,460 |
| checkBalance | 64 | 58,251 | 54,728 | 3,523 | 164,480 | 164,480 |
| withdraw | 1 | 24,522 | 24,434 | 88 | 46,278 | 46,190 |
| withdraw | 16 | 18,840 | 17,432 | 1,408 | 46,241 | 44,833 |
| withdraw | 64 | 55,370 | 49,738 | 5,632 | 100,613 | 94,981 |

Execution savings are 55 gas per balance plus 3 fixed gas for checkBalance,
and 88 gas per balance for withdraw. Larger checkBalance transactions retain
identical receipt gas despite lower execution cost: their receipts exactly match
the [EIP-7623 calldata gas floor](https://eips.ethereum.org/EIPS/eip-7623),
`21000 + 10 * (zeroBytes + 4 * nonzeroBytes)`. The benchmark records that floor
alongside each result. Report both measurements rather than equating an execution
saving with a transaction saving. Withdrawal
rows accumulate storage on both hosts equally: count 1 creates the slot, later
rows update it, explaining its higher single-item cost. Combined host runtime
falls from 2,903 to 2,897 bytes, including the measurement wrapper.

Results and compiler settings are written to
`.npm-cache/command-balance-decoder-results.json`. Regression tests cover paired
source advancement, full-width values, logical state bounds despite physical
trailing input, header-before-bounds errors, and rollback of earlier hook writes.

Verification: all 1,896 regular tests, the focused command benchmark, and
TypeScript typechecking passed. The regular suite used the already-compiled
artifacts from the cached native compiler configuration described above.

### Deferred cursor conversion

`length(cur)` returns the remaining byte count, ignoring metadata. It trusts
current <= end and performs no repeated validation or cursor advancement.

`hash(cur)` hashes exactly [current, end), copying calldata to temporary free
memory for KECCAK256 without allocating bytes or changing the free-memory pointer.
Like conversions, it requires validated bounds and does not skip a header.


`toBytes(cur)` returns `bytes calldata`; `toString(cur)` returns `string calldata`
by reusing toBytes. Both expose [current, end), ignore cursor metadata, and neither
advance the cursor nor allocate or copy memory. They do not skip block headers:
pass the payload cursor returned by unpack when a payload is desired.

The caller must already establish current <= end <= calldatasize. These helpers
perform no header, bounds, provenance, or UTF-8 checks. A packed cursor alone is
not proof of a valid calldata range. Assigning the returned string to a
`string memory` variable requests a copy at that point.

```solidity
uint nameCur;
(nameCur, exec.input) = CursorBlocks.unpackString(exec.input);
// Pass nameCur to other helpers until the text is needed.
string calldata name = CursorBlocks.toString(nameCur);
```

Focused conversion tests cover empty, unaligned, advanced, and metadata-bearing
ranges, arbitrary byte contents, Unicode text, explicit memory conversion, and
unchanged calldata offsets/free-memory pointer during view conversion.

### Retired empty-block convention

Dedicated empty-block helpers have been removed from Blocks, Decoders, Writers,
and Executions, including their obsolete test and benchmark operations. The
schema convention no longer defines `maybe` or a universal header-only empty
form for arbitrary block types. Bytes, strings, and lists retain valid empty
payloads; fixed and composite blocks must satisfy their actual payload schema.
Specs.Empty still declares an absent stream. Historical optimization notes above
may refer to removed helpers and do not define the current API.
