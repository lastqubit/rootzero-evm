# Encoder

`Buffers` has been removed from the production API. Use Encoder for buffer
initialization, reservation, growth, and finalization. `LegacyBuffers` is retained
only under contracts/test for historical comparisons, outside the package.

Complete-child creator measurements below are historical and use the test-only
`PreviousContextCreator`; that API has been removed from Encoder.

The creator API includes the fixed layouts supported by the writers. These allocate the final block once and compose `writeHeader` and
`write32`, preserving full-width fields without semantic validation.

`createBlock(key, data)` accepts a memory payload or a validated calldata payload
cursor. `createList`, `createBytes`, and `createString` are thin named wrappers;
their inputs exclude the header and may be empty. Memory text uses `bytes`.
Creators always construct new blocks from values and payloads; there is no
complete-block copy creator or `create...Wrap` variant. Composite writers retain
the `Wrap` distinction for payloads versus complete children.
All results have zero allocation padding, and total sizes must fit uint32.

`contracts/codec/Encoder.sol` implements the block encoders used by Execution
output helpers independently of `Blocks`. CONTEXT creators accept state and input
payloads and construct STATE and INPUT headers:

```solidity
bytes memory value = Encoder.createContext(account, state, input);
(dst, cur) = Encoder.writeContextWrap(cur, dst, account, state, input);
```

Memory overloads use `bytes memory state` and `bytes memory input`.
Cursor overloads use `uint stateCur` and `uint inputCur`. Function names and
NatSpec specify whether child headers are included for writers; creator inputs
always exclude those headers. A cursor selects its remaining calldata
range: low 32 bits hold the current position, the next 32 its exclusive end.
Metadata is ignored. Cursors must already satisfy current <= end <= calldatasize.
The encoder copies that range directly, without materializing intermediate bytes,
skipping headers, advancing cursors, or validating nested streams.

All block writers take `(cur, dst, ...)` and return `(dst, nextCur)`. They reserve,
grow, and advance the destination internally. Primitive writes return an absolute
`nextAbs` for composing each block sequentially. The former offset-based block
writers now live only in `contracts/test/ReservedBlockEncoder.sol` as benchmark
baselines; they are no longer part of `Encoder`.

Multi-value returns consistently place the updated cursor last:
`init` returns `(dst, cur)`, `reserve` returns `(dst, abs, nextCur)`, and block
writers return `(dst, nextCur)`. Cursor arguments remain first.

The return-order benchmark (`test/encoder-order.bench.test.ts`) compares identical
consumers against the previous cursor-first returns, using solc 0.8.35, viaIR,
optimizer 200, and Cancun. Both candidates now reserve the same logging prefix
to isolate return ordering. The original 78-case measurements below predate that
prefix: output bytes, cursor metadata, and memory allocation matched. With exact
capacity, balance writes cost 5 more gas per
block; all four context variants save 12 gas per block. Starting from zero
capacity, 1/2/4 balance writes cost 21/42/68 more gas; context savings are unchanged.
Both benchmark contracts have 1,555 bytes of executable runtime code. These are
measurements of this consumer loop, not a guaranteed cost for every caller.

## Growable cursor writers

The cursor-based writers keep the entire writer lifecycle inside
`Encoder`. Every buffer is growable, and initialization allocates immediately:

```solidity
(bytes memory dst, uint cur) = Encoder.init(capacityHint);
(dst, cur) = Encoder.writeBalance(cur, dst, asset, amount);
(dst, cur) = Encoder.writeContext(cur, dst, account, stateCur, inputCur);
bytes memory result = Encoder.finish(cur, dst);
```

Both returned values must be retained: growth can relocate `dst`. A destination
cursor holds the relative written position in its low 32 bits and logical capacity
in the next 32; higher metadata is preserved. Source cursors still refer to
absolute calldata ranges. Complete-child and Wrap overloads follow the same
source conventions as the existing encoders.

Custom writers calculate their sizes once and compose the same primitives:

```solidity
uint stateSize = Encoder.length(stateCur);
uint inputSize = Encoder.length(inputCur);
uint size = 40 + stateSize + inputSize;
uint abs;
(dst, abs, cur) = Encoder.reserve(cur, dst, size);
unchecked { abs = Encoder.writeHeader(abs, Keys.Context, size - 8); }
abs = Encoder.write32(abs, account);
abs = Encoder.copy(abs, uint32(stateCur), stateSize);
Encoder.copy(abs, uint32(inputCur), inputSize);
```

Cursor writers use this flow directly, rather than reserving and calling an
offset writer that computes the sizes again. `reserve` handles only position,
capacity, allocation, and advancement; it returns the absolute destination for
the first write. Its uncommon allocation path is separate from the small normal
reservation path. Low-level `grow(dst, written, capacity)` allocates and copies
only the written prefix; its private cursor overload selects geometric capacity.

Allocations retain a full scratch word beyond rounded logical capacity. Writers
reserve only logical bytes, including Wrap writers whose final header may touch
24 extra bytes. Capacity doubles from the hint (starting at 64 when zero), as in
`Buffers`; a doubling beyond uint32 capacity is rejected rather than clamped.

This is a trusted writer lifecycle, not a validator for arbitrary cursor/buffer
pairs. Start with the allocated pair returned by `init`, fully initialize each reservation,
and preserve the returned pair. Unused capacity is uninitialized and must not be
read or exposed. `finish` exposes only written bytes and clears trailing padding;
it ends the writer lifecycle. Memory sources must remain disjoint from writes.
These invariants replace repeated physical-buffer checks in the old reservation
path. Executions uses the cursor API; Bootstrap and Debit use the specialized
Execute output helpers. Execution opening initializes eagerly. `open`, `openInput`, and
`openContext` allocate the output writer once; output helpers contain no lazy
initialization checks. Scaled `openInput` and `openContext` overloads take
`numerator` and `denominator` after the calldata source. They calculate the
base hint once, apply floor division, and allocate only the scaled capacity.
A zero numerator starts with zero capacity; later writes still grow the buffer.
Zero denominators revert ZeroAmount. Intermediate multiplication overflow or
a final capacity above uint32.max reverts ValueOverflow. The uint32 limit is
applied after scaling, so an oversized base hint can be reduced before allocation.
The legacy `scaleOutput` helper remains removed from Executions. Both command runner and
execution finalization use Encoder. Existing output allocated by other
writer helpers meets the cursor writer backing-memory requirements.

`test/encoder-buffer.test.ts` covers every cursor writer, growth, metadata,
capacity boundaries, dirty memory, padding, and retained scratch allocations.
`test/encoder-buffer.bench.test.ts` compares against `Buffers.reserve` plus the
frozen test-only offset writer, including finalization. Warm tests preallocate and touch
both buffers before timing; allocation and growth tests include those costs.
Outputs are checked against independent encodings for every benchmark row.
Results are recorded in `.npm-cache/encoder-buffer-results.json`.

Historical lazy-prototype measurements before eager initialization was adopted.
Solidity 0.8.35, viaIR, optimizer 200, Cancun; gas includes finalization:

| Four writes | Existing flow | Cursor writer | Difference |
| --- | ---: | ---: | ---: |
| BALANCE, existing capacity, dedicated loop | 1,415 | 1,449 | +34 |
| BALANCE, first allocation, dedicated loop | 1,842 | 1,648 | -194 |
| BALANCE, growth from zero, dedicated loop | 3,497 | 2,583 | -914 |
| CONTEXT memory, existing capacity | 2,980 | 2,993 | +13 |
| CONTEXT calldata, existing capacity | 3,228 | 3,213 | -15 |
| CONTEXT Wrap calldata, existing capacity | 3,808 | 3,505 | -303 |
| CONTEXT Wrap calldata, first allocation | 4,272 | 3,717 | -555 |
| CONTEXT Wrap calldata, growth from zero | 5,219 | 4,629 | -590 |

CONTEXT rows use 32-byte state and input payloads. These are helper-loop
measurements, not command transaction estimates. The dedicated BALANCE loop
also finds a +1,534 gas regression for 64 writes into existing capacity, versus
a 2,542 gas saving when growing from zero. The new lifecycle is therefore not
uniformly faster. Allocation savings come from avoiding zeroing unused capacity;
normal-path differences also depend on compiler inlining and call-site shape.
Keeping the old reservation callers during this experiment allows direct comparison.

Growth allocation sizes need not match for Wrap: the old path counts 24 scratch
bytes toward logical capacity. For four 32-byte-payload Wrap contexts, it allocates
896 cumulative bytes versus 1,088 in the new path, because it starts with a larger
first allocation and consequently grows fewer times. The benchmark reports both
gas and cumulative allocation rather than assuming memory usage always improves.

## Eager initialization for short flows

The primary workload is an accurate capacity hint and one to four writes.
`Encoder` now uses the winning eager relative design.
`contracts/test/EagerAbsoluteEncoder.sol` retains the absolute alternative, and
`LazyRelativeEncoder.sol` freezes the former lazy lifecycle for comparison. The eager implementations
keep sequential `writeHeader`, `write32`, `wrap`, and `copy` composition and
calculate composite sizes once. `Encoder.init(capacity)` now returns `(dst, cur)` and allocates the buffer.
Only the alternative implementations remain test-only.

The API allocates and returns the complete writer state:

```solidity
(bytes memory dst, uint cur) = Encoder.init(capacity);
(dst, cur) = Encoder.writeBalance(cur, dst, asset, amount);
bytes memory result = Encoder.finish(cur, dst);
```

Every initialized buffer has backing memory and retained scratch, even at zero
capacity. `reserve` computes remaining capacity by unchecked subtraction of
validated cursor lanes, then compares `size` against that space. On success,
unchecked advancement is proven safe without a checked `position + size` sum.
There is no unallocated-buffer check in the write path. Only the growth path
calculates the larger required capacity and checks overflow. `finish` trims and
clears padding in place, including for an unused buffer; no separate empty
result allocation is necessary. All buffers remain growable.

Solidity 0.8.35, viaIR, optimizer 200, Cancun. These measurements include **init,
allocation, every write, and finish** in the same timer; previous warm-buffer
measurements did not include initialization and should not be compared directly.

| Correctly sized workload | Previous lazy relative | Eager relative | Eager absolute |
| --- | ---: | ---: | ---: |
| 1 BALANCE | 709 | **440** | 537 |
| 2 BALANCE | 1,019 | **677** | 753 |
| 3 BALANCE | 1,329 | **914** | 969 |
| 4 BALANCE | 1,639 | **1,151** | 1,185 |
| 1 CONTEXT Wrap calldata | 1,202 | **928** | 1,025 |
| 4 CONTEXT Wrap calldata | 3,684 | **3,101** | 3,162 |

CONTEXT examples use two 32-byte payloads. Eager relative wins all 69 exact-capacity
rows, covering unused output, BALANCE, and all four CONTEXT overloads with payload
sizes 0, 1, 32, and 257. It also improves every tested growth-from-zero row versus
the previous lazy relative version; four growing BALANCE writes cost 2,271 versus
2,585 gas. Eager absolute removes address conversion per reservation, but its
initialization and address packing costs outweigh that saving in these short
flows. The preferred candidate for the stated workload is therefore **eager
initialization with relative cursor lanes**.

The result is for this combined set of primitive changes, not a claim that all
savings come from eager allocation alone. The lifecycle implementation is local
to `Encoder`; it does not delegate to `Buffers`, `Blocks`, or `Writers`.
Its only imports are schema keys and the shared overflow error. Input materialization is outside the
timer and identical across candidates. Benchmark output is checked against an
independent encoding on every row; dirty-memory, scratch-guard, metadata,
overflow, empty-buffer, and growth tests cover the new invariants.

Run `npm run bench -- test/eager-encoder.bench.test.ts`; the 138 scenario rows
are saved in `.npm-cache/eager-encoder-results.json`. Run focused behavior tests
with `npm test -- test/eager-encoder.test.ts`.

## Absolute destination cursor experiment

`contracts/test/AbsoluteEncoderBuffer.sol` tests native memory addresses without
changing the production library's relative destination format. Once allocated,
its low 32 bits hold the current write address and the next 32 hold the capacity
end address. `reserve` can return the current address directly. Growth recovers
the written length and capacity relative to the old buffer, copies the initialized
prefix, then rebuilds both addresses for the new allocation. Finalization also
converts the address back to a byte length.

Lazy initialization still needs a sentinel: before allocation, a zero position
means the upper field is a capacity hint, not an absolute end. An always-absolute
format would require allocation during initialization (or a different place to
store that hint). Absolute addresses and capacity ends must fit uint32; the
prototype checks the relocated end before allocating. Saved memory addresses
must not be reused after relocation.

Solidity 0.8.35, viaIR, optimizer 200, Cancun, including finalization:

| Workload | Relative | Absolute | Absolute difference |
| --- | ---: | ---: | ---: |
| 4 BALANCE, existing capacity | 1,449 | 1,414 | -35 |
| 4 BALANCE, first allocation | 1,648 | 1,768 | +120 |
| 4 BALANCE, growth from zero | 2,583 | 2,985 | +402 |
| 64 BALANCE, existing capacity | 21,249 | 20,314 | -935 |
| 64 BALANCE, first allocation | 21,896 | 21,116 | -780 |
| 64 BALANCE, growth from zero | 25,904 | 26,102 | +198 |
| 4 CONTEXT Wrap calldata, existing capacity | 3,505 | 3,432 | -73 |
| 4 CONTEXT Wrap calldata, first allocation | 3,717 | 3,834 | +117 |
| 4 CONTEXT Wrap calldata, growth from zero | 4,629 | 5,128 | +499 |

CONTEXT uses 32-byte state and input payloads; the other three CONTEXT overloads
show the same differences for this workload. Both representations use identical
allocation primitives, growth policy, scratch space, and encodings. Warm buffers
are allocated and touched before timing; first-allocation and growth rows include
those costs. The dedicated BALANCE loop avoids the multi-encoder dispatch.

This favors absolute cursors for sufficiently long streams with good capacity
hints, but does not establish an overall win for growable writers. The subsequent short-flow experiment above selected eager relative cursors. Tests cover relocation,
metadata, dirty memory, scratch guards, empty writers, address limits, and all
five writer variants. Run `npm run bench -- test/absolute-encoder-buffer.bench.test.ts`;
results are in `.npm-cache/absolute-encoder-buffer-results.json`.

## Execution output migration

All named Execution output writers delegate to Encoder. Structured
overloads delegate to their scalar counterparts. Calldata sources now pass
directly as uint cursors; outputCopy names and the slice-to-cursor adapter have
been removed. Cursor sources must already be valid calldata ranges.

Default cursor overloads copy complete blocks, preserving their headers.
For composites, each supplied source is a complete BYTES child (STRING for
LABEL/SCHEMA). Cursor Wrap helpers take payloads and create those headers.
Neither variant advances or revalidates its sources. The custom payload adapter
outputBlockWrap(exec, spec, dataCur) retains Specs.validate against the selected
payload length; outputBlock(exec, dataCur) copies a complete validated block.

| Complete-block cursor | Payload cursor |
| --- | --- |
| outputBlock(exec, blockCur) | outputBlockWrap(exec, spec, payloadCur) |
| outputList / outputBytes / outputString | outputListWrap / outputBytesWrap / outputStringWrap |
| outputStep / outputCall / outputDispatch | outputStepWrap / outputCallWrap / outputDispatchWrap |
| outputRelay / outputContext / outputRecover | outputRelayWrap / outputContextWrap / outputRecoverWrap |
| outputLabel / outputSchema | outputLabelWrap / outputSchemaWrap |

For example, take returns a complete block for outputBlock; unpack returns
a payload for outputBlockWrap. outputContext(exec, account, stateCur, inputCur)
copies complete STATE and INPUT children. outputContextWrap with those arguments expects
only their payloads. Existing memory output overloads retain their payload API;
this migration changes the calldata-source API.

Cursor construction and representability checks belong at the source boundary,
not at each output write. The benchmark constructs valid source cursors before
the timed repeated writes, and tests forged slice lengths at that boundary.
No output helper calculates its block size or reserves memory separately.
`Executions.reserve(exec, size)` delegates directly to `Encoder.reserve`
and returns an absolute memory address for custom raw writers. There is no
separate touch argument; the encoder retains a trailing scratch word. Named
output helpers reserve internally. Executions no longer depends on Buffers.

Execution stores its output cursor in `uint output` and the backing memory in
`bytes buffer`. With `using Encoder for uint`, writes follow the same pattern:
`(exec.buffer, exec.output) = exec.output.writeBalance(exec.buffer, asset, amount)`.
Input and state cursors select absolute calldata ranges; the output cursor holds
the written offset and logical capacity within the buffer.

Supported fixed types are ACCOUNT, ASSET, NODE, STATUS, LIMITS, ASSET_AMOUNT, BALANCE,
ASSET_LIABILITY, ACCOUNT_ASSET, HOST_ASSET, ALLOCATION, ALLOWANCE, CUSTODY,
ACCOUNT_AMOUNT, HOST_AMOUNT, HOST_ACCOUNT_ASSET, QUOTE, TRANSACTION,
HOST_ACCOUNT_AMOUNT, and POSITION. Each reserves once, writes its header,
and writes full-width fields in schema order.

`writeBlock(cur, dst, key, data)` wraps a memory or calldata-cursor payload.
`writeList`, `writeBytes`, and `writeString` are thin named wrappers. Memory
strings are passed as `bytes(text)`. These leaf inputs exclude the outer header.
Composite payload writers use `writeStepWrap`, `writeCallWrap`,
`writeDispatchWrap`, `writeRelayWrap`, `writeRecoverWrap`, `writeLabelWrap`,
`writeSchemaWrap`, and `writeContextWrap`, each with memory and source-cursor
overloads. Label and Schema add STRING children; the other composites add BYTES
children. The corresponding default cursor writers copy complete child blocks
using the same size/reserve/header/word/copy sequence. The three-argument
writeBlock(cur, dst, dataCur) reserves once and copies a complete block verbatim;
the keyed overload and its named leaf wrappers construct a header around a payload.

The library keeps low-level primitives first, fixed writers ordered by payload
size, generic and named payload writers next, and composites and creators after
those. Encoding is independent of `Blocks`; ordinary readers in Executions
delegate to `Blocks` while output helpers delegate to `Encoder`.

`test/encoder-outputs.test.ts` checks all twenty fixed layouts against independent
encodings and legacy outputs, including full-width fields, exact capacity, and
growth. It also checks memory/cursor payload wrappers. The composite benchmark
checks all existing output layouts, empty children, unaligned lengths, repeated
writes, equal allocations, and identical overflow errors before forged payloads
can be read.

With solc 0.8.35, viaIR, optimizer 200, Cancun, representative single-write savings
are 74-78 gas for fixed blocks with correct capacity (including initialization and
finalization), 302 gas for memory CONTEXT, 35 gas for calldata CONTEXT, and 47 gas
for calldata BYTES (32-byte payload fixtures, write-only dynamic timings).
Calldata RELAY regresses by 75 gas in the corresponding fixture; conversion of
both raw slices to checked cursors adds work. The benchmark records regressions
rather than asserting every new implementation must be faster. Source cursors
passed directly to the encoder do not pay the raw-slice conversion cost.

Run `npm run bench -- test/encoder-outputs.bench.test.ts
 test/execution-output-optimization.bench.test.ts` (on one line). Results are in
`.npm-cache/encoder-output-fixed-results.json` and
`.npm-cache/execution-output-results.json`. Fixed measurements include the full
writer lifecycle; dynamic measurements exclude input materialization, initial
allocation, and a common prefix and include growth during the measured writes.

Historical BALANCE-only migration notes follow:

`writeBalance(cur, dst, asset, amount)` appends a 72-byte BALANCE and returns
the advanced cursor and possibly relocated buffer. `createBalance(asset, amount)` allocates a padded result with
the same 72 logical bytes. Both compose `writeHeader` and `write32`; the creator
also uses `allocate` and `pos`. The creator composes those primitives directly:
delegating to the returning writer added 38 gas per creation in the tested harness.

`Executions.outputBalance`, `Writers.appendBalance`, and the direct Bootstrap and
Debit pipeline writers now use `Encoder`. Reservation and advancement now happen inside the cursor writer. Bootstrap and
Debit now allocate the final output through `Execute.allocateBalances` and write
within it directly, without growth or finalization. Bootstrap derives its exact
count from the inner AssetAmount list.
At that intermediate stage, Writers also initialized and finalized through Encoder;
its remaining formats still used the old helpers. Writers has since been removed. `Codec.sol` exports the library.

Solidity 0.8.35 viaIR, optimizer 200, Cancun measurements:

| Workload | Old Blocks | Encoder |
| --- | ---: | ---: |
| Write 16 consecutive balances | 2,270 | 2,168 |
| Create 16 balances | 3,248 | 3,199 |
| checkBalance, 16 balances, measured call gas | 15,947 | 15,803 |
| debitAccount, 16 balances, measured call gas | 23,872 | 23,728 |

Both real command entrypoints save 9 execution gas per balance. Receipt savings
can be hidden by the calldata gas floor (as observed for checkBalance batches).
The debit hook records debited amounts in storage, without token transfers. Its
storage is already nonzero after earlier transactions in the benchmark; old and new hosts
receive identical calls and retain identical balances. The comparison freezes
the old outputBalance implementation; decoding and runners remain shared.
The table above records the earlier offset-writer migration; current cursor
migration measurements are regenerated by the same command benchmark. Creators retain 32 fewer bytes per result than old Blocks.

Run `npm run bench -- test/balance-encoder.bench.test.ts`. The benchmark records
primitive and real-command results in `.npm-cache/balance-encoder-results.json`
and `.npm-cache/balance-encoder-command-results.json`. Focused tests exercise
unaligned writes, adjacent guard bytes, full-width values, Writer growth, and
historical offset-writer chaining through the test-only baseline and current
cursor-writer chaining through the eager lifecycle tests.

## Wrapping payloads

The `Wrap` suffix adds the schema-specific child headers around payloads. Both memory and calldata
cursor overloads are supported. The function name and NatSpec distinguish memory
payloads from complete blocks; memory parameter names remain state/input:

```solidity
bytes memory value = Encoder.createContext(account, state, input);
(dst, cur) = Encoder.writeContextWrap(cur, dst, account, stateCur, inputCur);
```

For Context complete-child helpers, `stateCur` and `inputCur` must select exactly
one validated STATE and INPUT block respectively. An empty payload still has an
eight-byte typed header. The helpers trust
that validation, copy the children intact, and write only the outer CONTEXT header
and account. Cursor metadata is ignored, and source cursors are unchanged.
`writeContext` reserves its complete destination range. Memory sources must not
overlap destination writes. The cursor writer checks capacity through `reserve`;
the creator checks total size through `allocate`.

Use `inputCur`/`stateCur` for both complete blocks and payloads, with the function
contract declaring the required range. `Blocks.take` supplies complete block ranges;
`unpack` supplies payload ranges. No helper infers the representation
or checks the headers again.

In the isolated 16-call viaIR benchmark, compared with the corresponding payload
helpers, complete-child copying saves approximately:

| Source | Create, gas/call | Write, gas/call |
| --- | ---: | ---: |
| Calldata cursors | 60-66 | 81-87 |
| Memory | 60-66 | 84-90 |

These measurements assume complete child blocks already exist. Constructing or
validating those children is outside the timer; generating them just to copy them
is not the intended optimization. Source sizes straddle copy-word boundaries.
Results are saved to `.npm-cache/block-encoder-copy-results.json` by the same
benchmark suite, and correctness is covered by `test/block-encoder-copy.test.ts`.

## Primitive boundary

All primitives are internal library helpers, available for composing custom
encoders. Writes and copies return the next absolute memory position:

| Primitive | Purpose |
| --- | --- |
| `allocate(size)` | Allocate the final result, check uint32 size, clear padding |
| `pos(dst, offset)` | Select an absolute memory write position |
| `length(cur)` | Read the remaining length of a validated calldata cursor |
| `writeHeader(abs, key, size)` | Write eight header bytes and advance |
| `write32(abs, value)` | Write a word and advance |
| `copy(abs, source)` | Copy memory bytes or a calldata cursor unchanged and advance |
| `wrap(abs, key, payload)` | Write a header plus memory/cursor payload and advance |

The sized copy/wrap overloads accept a memory source or absolute calldata source
position and a known length. CONTEXT helpers cache lengths for total-size arithmetic
and pass them through, avoiding repeated reads/decoding. Both the convenience and
sized wrappers compose the same underlying primitives. Memory uses MCOPY; calldata
uses CALLDATACOPY. All position arithmetic in primitives is unchecked, and all
source/destination bounds are caller preconditions.

For example, after reserving enough destination memory and any header scratch:

```solidity
uint abs = Encoder.pos(dst, offset);
abs = Encoder.writeHeader(abs, key, payloadSize);
abs = Encoder.write32(abs, value);
abs = Encoder.wrap(abs, Keys.Bytes, inputCur);
abs = Encoder.copy(abs, constraintCur); // Complete encoded constraint block.
```

This encodes a fixed word, wraps a payload, and copies an existing child intact.
The custom-schema test exercises this composition with memory and calldata inputs
and verifies both the encoded bytes and the final write position.

Payload writers allocate nothing and do not resize or check the destination.
Reserve the complete block plus 24 writable scratch bytes after it, prove the
complete size fits uint32, and keep memory sources disjoint from all writes.
Header stores can overwrite scratch. Default CONTEXT writers need no trailing scratch.
Creators use temporary free memory and retain only the rounded final allocation;
fill their output before making further allocations when using that scratch.

There are no CONTEXT-specific layout primitives. Compared with the previous
specialized implementation, the sequential version changes internal gas per call
as follows (16-call benchmark, rounded where loop overhead contributes):

| Path | Calldata | Memory |
| --- | ---: | ---: |
| Create payload children | +9 | unchanged |
| Write payload children | +33 | -12 |
| Create complete children | -9 | -6 |
| Write complete children | +6 | -40 |

The generic wrap helpers compile to the same gas as explicit header/copy steps.
The overall refactor is not free on every path; these tradeoffs remain visible
in these historical measurements. The cursor length primitive widens the
subtraction to uint256 to avoid an unnecessary uint32 result mask.

## Measured comparison

### Boolean representation experiment

`test/block-encoder-flags.bench.test.ts` benchmarks a test-only shared encoder
accepting one boolean per child: false means payload, true means complete BYTES
block. `Encoder` retains its explicit APIs. The candidate caches lengths and
uses the existing primitives. Both memory and calldata overloads are tested for
creation and writing, including both mixed representations.

Literal booleans are passed directly at the helper call site. Runtime booleans
come from external arguments. The baseline calls existing Wrap/default helpers
for uniform representations, and composes the primitives explicitly for mixed
representations. Every contract shares the same timed-loop harness. Setup, memory
conversion, destination allocation for writers, and guard initialization are
outside timing; loop overhead and writer/source dispatch remain inside.

With viaIR, optimizer 200 runs, Solidity 0.8.35 and Cancun, extra gas per operation
versus explicit helpers for one-byte child payloads (16-call loop):

| Children | Literal create | Literal write | Runtime create | Runtime write |
| --- | ---: | ---: | ---: | ---: |
| Payload / payload, calldata | 0 | 0 | about 299 | about 184 |
| Payload / payload, memory | 0 | 0 | about 291 | about 184 |
| Block / block, calldata | +9 | +6 | about 262 | about 155 |
| Block / block, memory | +9 | +6 | about 254 | about 155 |

Mixed literal cases vary with compiler layout: calldata candidates are cheaper
than the explicit mixed baseline, while memory candidates cost more. Runtime
flags cost more in every tested case. These are internal-loop measurements,
not transaction gas or a universal cost for a boolean parameter.

Size arithmetic matters: start the flag-dependent prefix with `uint(40)` and add
the fixed header contributions before the variable child lengths. Otherwise,
narrow intermediate arithmetic or additional checked additions can survive
compilation even with literal flags. A literal-returning function at the caller
also did not optimize as well as literal flags directly at the encoder call.

The benchmark checks encoded output, allocation sizes, source preservation,
prefix/suffix guards, empty children, and copy-word boundaries with counts 1 and
16. Raw results are written to `.npm-cache/block-encoder-flags-results.json`.
Run `npm run bench -- test/block-encoder-flags.bench.test.ts` to reproduce.

### Existing helper comparison

Solidity 0.8.35, viaIR, optimizer 200 runs, Cancun. Internal gas for 16 calls;
negative deltas favor Encoder:

| Operation | State/input bytes | Blocks | Encoder | Delta |
| --- | --- | ---: | ---: | ---: |
| Create, cursor | 0 / 0 | 10,198 | 10,245 | +47 |
| Write, cursor | 0 / 0 | 6,754 | 7,396 | +642 |
| Create, cursor | 257 / 2048 | 20,056 | 20,035 | -21 |
| Write, cursor | 257 / 2048 | 10,258 | 10,900 | +642 |
| Create, memory | 0 / 0 | 10,608 | 9,359 | -1,249 |
| Write, memory | 0 / 0 | 6,290 | 4,900 | -1,390 |
| Create, memory | 257 / 2048 | 20,822 | 19,502 | -1,320 |
| Write, memory | 257 / 2048 | 9,794 | 8,404 | -1,390 |

Creators retain 32 fewer bytes per result. Writers retain no additional memory.
Cursor payload writing is about 40 gas/call more expensive than old Blocks here;
memory payload writing saves about 87 gas/call. Setup, source conversion, buffer reservation, and guard initialization
are outside the timer. Loop and dispatch overhead are included. Writers repeatedly
overwrite the same reserved buffer; creators allocate a fresh result per iteration.
Writer and creator consumers are compiled separately: combining call sites can
change optimizer inlining, so these are not real-command or transaction gas claims.
Old writers still use their existing Solidity arithmetic checks; the new writer
uses unchecked layout arithmetic under its documented uint32 size precondition.

Run `npm run bench -- test/block-encoder.bench.test.ts` to regenerate measurements.
The benchmark writes `.npm-cache/block-encoder-results.json` with compiler settings
and results for counts 1 and 16 and multiple empty, unaligned, and large payloads.
Focused tests in `test/block-encoder.test.ts` cover cursor metadata and subranges,
round trips through Blocks, guarded writes, unchanged source memory, dirty
allocation padding, subsequent allocations, and oversized-result rejection.


## Complete-block and payload cursor comparison

The execution-output-cursors tests cover all twelve pairs, empty and unaligned
payloads, selected subranges with surrounding bytes, metadata, repeated writes,
growth and sufficient initial capacity. They also pass Blocks selections
directly into output and retain custom payload spec validation.

With solc 0.8.35, viaIR, optimizer 200 and Cancun, a single write of a 33-byte
payload into an exactly sized buffer used 32?91 less gas when copying existing
headers. STEP/CALL/DISPATCH/RECOVER/LABEL/SCHEMA saved 32, CONTEXT 53 and RELAY 59.
This fixture includes dispatch/loop overhead and starts with ready validated
cursors. It excludes the cost of producing or validating source blocks and
transaction intrinsic calldata gas. It does not justify creating blocks merely
to copy them: use the form matching the input already available.

Run execution-output-cursors.bench.test.ts for the two cursor forms and
execution-output-optimization.bench.test.ts for the legacy writer comparison.

## Scaled execution opening

```solidity
exec.openInput(descriptor, budget, input, 3, 2);
exec.openContext(descriptor, budget, context, 1, 2);
```

Default overloads retain their signatures and bypass scaling. Both forms reuse
source initialization, preserving cursor bounds, context validation, account,
and budget. `test/scaled-opening.bench.test.ts` compares the defaults against
frozen implementations: all 40 cases have identical gas, returned fields, and
memory footprint with solc 0.8.35, viaIR, optimizer 200, and Cancun. Cases cover
input/context opening, fixed/scanned counts, 0/1/2/4/16 blocks, and output hints
present/absent. This result applies to those benchmark consumers.

## Reserved state blocks and logging

`Encoder.writeBalanceAt(abs, asset, amount)` and
`Encoder.writePositionAt(abs, asset, amount, liability, debt, counterparty)`
write a complete block into an already reserved memory range and return its
end address. Struct overloads accept `AssetAmount` and `Position` and copy their
payload directly. The caller owns 72 or 168 writable bytes respectively; struct
sources must not overlap the destination block. These primitives do not allocate,
validate, reserve, or advance a writer. Growable scalar writers share these
primitives. Structured execution outputs reserve once and use the struct writer.

`exec.outputBalance(...)` and `exec.outputPosition(...)` only append blocks.
Select output lane codes to log the complete output through the endpoint runner,
or use `exec.finish(id, descriptor)` / `exec.close(id, descriptor)` in custom loops.
See [output finalization](#output-finalization-and-logging).

### Correlated streams

`Logs.stream(correlationId, abs, size)` emits a tagged correlation ID
followed by an existing block stream using `LOG0`. The ID's highest byte MUST be
`Logs.Stream` (`0x00`). The helper emits the full ID unchanged and performs no
validation, packing, allocation, or copying.

The caller owns an initialized valid block stream at the absolute position and
**32 writable bytes immediately before it**. The helper saves that preceding
word, overwrites it with the ID, logs, and restores it exactly. Payload and
free-memory pointer remain unchanged. Standard bytes payloads have their length
word immediately before them, so finalized bytes can be used directly:

```solidity
Logs.stream(correlationId, Encoder.pos(output, 0), output.length);
```

An active Encoder buffer can also be logged using its written length (not capacity),
or a subrange can be selected when the preceding-word requirement is satisfied.
The pointer and size are trusted; no bounds or block-framing checks are performed.
See the [wire format](Indexing.md#correlated-block-stream-logs) for indexer rules.

### Codes and block-stream primitives

`Logs.mem(codes, abs, size)` and `Logs.copy(codes, abs, size)` both emit exactly
`uint256 codes | block stream` using `LOG0`, without topics, a format tag, ABI
wrapper, or padding. All 256 bits of codes are emitted unchanged. The caller
establishes block validity and code semantics; neither primitive validates them.

`mem` takes an absolute memory address and initialized byte length. The caller
owns the stream and the 32 writable bytes immediately before it. The helper saves
that word, writes codes, logs, and restores it exactly. It performs no copying or
allocation. Address subtraction/addition and `size + 32` must not wrap. For bytes:

```solidity
Logs.mem(codes, Encoder.pos(output, 0), output.length);
```

For active Encoder buffers, use the written length rather than capacity and
reacquire the address after growth. Empty streams still need the preceding word.

`copy` takes an absolute calldata offset and byte length. The caller proves
`abs <= calldatasize()` and `size <= calldatasize() - abs`; a packed cursor must
be unpacked first. It stores codes at the free-memory pointer, copies the selected
bytes immediately afterward, and logs them. It leaves the free-memory pointer
unchanged and preserves allocated memory. The temporary range of `32 + size`
bytes must be available and its address arithmetic must not wrap. Its contents
are unspecified afterward; no pointer to it escapes. Out-of-bounds calldata is
zero-filled by the EVM, so valid source bounds are a caller requirement.

```solidity
// input is bytes calldata containing the complete block stream.
uint abs;
assembly ("memory-safe") { abs := input.offset }
Logs.copy(codes, abs, input.length);
```

These primitives coexist with the correlation-stream helper. Their wire formats
are not automatically distinguishable; see [Indexing](Indexing.md#codes-and-block-stream-logs).

### Single balance helper

`Logs.balance(bytes32 asset, uint amount, uint codes)` creates a BALANCE block
through `Encoder.createBalance` and emits it through `Logs.mem`. It requires no
existing writer or caller-managed scratch memory:

```solidity
Logs.balance(asset, amount, codes);
```

It emits exactly `codes | BALANCE block` (104 bytes), with full-width values and
no account, extra tag, or topics. Codes and the emitter's protocol define whether
the quantity is a credit/debit amount or an updated balance.

### Output finalization and logging

`exec.finish()` finalizes output without checking source consumption or changing
the budget. `exec.expectEnd()` requires both cursors to equal their exclusive ends,
rejecting pending data and overshot cursors. `exec.close()` combines that check,
finalization, and returning and clearing the remaining budget. Both no-argument
finalizers are pure and silent.

`exec.finish(id, descriptor)` also logs the finalized output when the descriptor
selects output logging. `exec.close(id, descriptor)` adds the consumption check
and budget drain. Logs contain `[id:32][OUTPUT header][output stream]`; returned
bytes remain the original stream. The ID must match the registered descriptor.

Batch runners finish after a complete loop over valid bounded cursors, then call
`drainBudget()`. One-shot runners use checked close. Custom loops that can exit
early must use `expectEnd()` or checked close when complete consumption is required.
Do not append after finalization. Low-level logging remains available through
`Logs.memWrap(id, Keys.Output, output)` for finished Encoder-owned buffers.

### Pipeline context logging

```solidity
Logs.pipeline(account, budget, codes);
```

This encodes `Encoder.createPipeline(account, budget)` and emits it through
`Logs.mem`: 32 bytes of codes plus a 72-byte PIPELINE block, without topics.
budget is the invocation's initial native-value budget. Nested pipelines preserve
the account; special implementations must explicitly log account switches and
restoration. The helper performs no authorization or execution. `Pipeline.pipe`
calls it at entry, including empty pipelines. See [Pipeline context](Schema.md#pipeline-context).


### Envelope logging

```solidity
Logs.envelope(portal, resources, key, digest, codes);
```

The helper constructs Encoder.createEnvelope and emits it through Logs.mem:
32 bytes of codes plus a 136-byte Envelope block. digest is keccak256 of the
exact forwarded payload; key remains an independent transport lookup key.
The caller defines scope and action codes. No hashing or transport occurs here.
See [Transport envelopes](Schema.md#transport-envelopes).

`Encoder.createBootstrap(uint budget, bytes memory balances)` creates one
composite BOOTSTRAP containing the budget and a LIST wrapping the supplied
ASSET_AMOUNT stream. It allocates the final 48 + balances.length bytes once.
The former three-scalar Bootstrap creator and fixed Bootstrap size/header
constants are removed.
