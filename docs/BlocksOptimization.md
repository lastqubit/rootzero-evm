# Blocks allocation and scanning

Block factories now reserve the same physical memory as before but initialize
only the 32 bytes after the logical output. Each private allocator caller writes
the complete logical result. This avoids zeroing the output immediately before
copying or writing its contents, while preserving alignment, padding, and trailing
scratch space for writers that store an eight-byte header with a full-word MSTORE.

`find` and `run` calculate the encoded block size once and use unchecked arithmetic
only where bounds prove safety: payload length is uint32, the loop establishes
position < limit, and the region check establishes size <= limit - position.
Malformed-block validation still precedes the key comparison, including when the
malformed block does not match the requested key. `runCount` is unchanged.

Run the comparison with:

```sh
npx hardhat test test/blocks-optimization.bench.test.ts
```

The benchmark retains the previous allocator/factory bodies and scan loops. It
compares exact output, logical length, allocation footprint, trailing initialized
bytes, and an adjacent memory guard. Factory memory is deliberately dirtied before
both measurements. Factory cases cover generic memory/calldata copies, contexts,
empty blocks, and balances, including lengths around word and header boundaries.
Scans compare results and revert data for valid blocks, truncated headers/payloads,
different keys, and starting positions at or beyond the logical limit.

With solc 0.8.35, optimizer 200 runs, Cancun target:

| Case | Previous execution gas | New execution gas | Saved |
| --- | ---: | ---: | ---: |
| Generic calldata factory, 256 bytes | 818 | 578 | 240 |
| Generic calldata factory, 4 KiB | 1,538 | 938 | 600 |
| Generic calldata factory, 64 KiB | 13,058 | 6,698 | 6,360 |
| Context factory, 4 KiB state + 1-byte input | 2,400 | 1,865 | 535 |
| Empty block factory | 456 | 353 | 103 |
| Balance factory | 814 | 668 | 146 |
| Find absent key through 64 blocks | 33,311 | 16,148 | 17,163 |
| Count 64 matching blocks | 34,197 | 17,055 | 17,142 |

The generic factory rows include the validated-length improvement described below.
These are instrumented execution measurements, not transaction gas. Factory
measurements exclude input preparation and dirtying memory, which also pays memory
expansion before timing. Scan harness branching contributes a small fixed offset
(the empty run measures 10 gas more); the per-block reduction is 268 gas for both
scan operations. Real caller inlining and transaction calldata charges affect totals.

JSON results are written to `.npm-cache/blocks-factory-results.json` and
`.npm-cache/blocks-scan-results.json`. The wire format and public helper signatures
are unchanged.

## Bounded header inspection

`peek` checks the absolute ordering once, caches the remaining region length, and
uses unchecked subtraction only after proving the operands are ordered. `hasAt`
and `isEmpty` retain their short-circuit boundary guards without redundant checked
subtraction. `isEmpty` compares the eight-byte header to the expected key followed
by a zero payload length.

Run `npx hardhat test test/block-inspection.bench.test.ts`. Frozen previous
implementations are compared against production for truncated headers, insufficient
logical regions, maximum payload declarations, zero/all-ones keys, positions at or
beyond the limit, and absolute positions near uint256 overflow. `hasAt` continues
to require only a complete matching header; `peek` still rejects an oversized
declared payload with `MalformedBlocks`.

Measured savings over 64 repeated inspections with solc 0.8.35, optimizer 200 runs:

| Helper | Gas saved per inspection |
| --- | ---: |
| peek | 205 |
| hasAt | 78 |
| isEmpty, matching key | 111 |
| isEmpty, mismatching key | 88 |

These include measurement-harness branching and are execution-gas comparisons,
not guaranteed savings in every inlined caller. Results are written to
`.npm-cache/block-inspection-results.json`.

## Reusing validated factory lengths

Generic `create`/`createCopy` and calldata LIST/BYTES/STRING factories now pass
their checked payload length to `writeSized`/`copySized` helpers. The
helpers do not repeat `max32`; callers have already validated the same length
before allocating the output. Standalone `write` and `copy` keep their original
direct implementations and checks. Routing them through the new helpers was
measured and rejected because it added 50–67 gas per direct writer call.

Run `npx hardhat test test/factory-validation.bench.test.ts`. The frozen baseline
uses the same optimized allocator, so these measurements isolate this change:

| Factory | Additional execution gas saved |
| --- | ---: |
| Generic memory | 82 |
| Generic calldata | 79 |
| LIST calldata | 123 |
| BYTES calldata | 123 |
| STRING calldata | 123 |

Savings were constant over payload lengths 0, 1, 31, 32, 33, 256, and 4,096.
Standalone writer measurements differ by -1/+11 gas from the baseline due to
the benchmark's branch routing; their implementation bodies are unchanged.
Results include harness overhead and may differ in other inlined callers.

Tests compare all output bytes and forge lengths of 2^32 and uint256.max to
verify that every factory and direct writer still rejects with `ValueOverflow`
before allocating or copying the oversized payload. Results are saved to
`.npm-cache/factory-validation-results.json`.

## Composite factories and decoding

STEP, CALL, DISPATCH, RELAY, CONTEXT, and RECOVER factories now reuse their
validated total allocation length when writing the outer header. Private
factory writers subtract the eight-byte header from the allocated byte array's
length instead of recalculating and rechecking payload lengths. The identical
two-word layouts share a helper. Standalone writers retain their existing bodies.

These six decoders and ANNOTATION now validate their final BYTES child with
`unpackTailBytes`. It compares the packed child header against the expected key
and the remaining parent length, then returns the parent's known end. The
remaining length must fit uint32, which also rejects subtraction underflow when
the parent is too short. Fixed-position additions remain checked, and earlier
children still use `unpackBytes`. This preserves the absolute readers' existing
zero-padding behavior; surrounding cursors still enforce logical bounds.

Run `npx hardhat test test/composites.bench.test.ts`. With Solidity 0.8.35,
optimizer runs 200, and Cancun, additional execution gas saved is:

| Layout | Memory factory | Calldata factory | Decoder |
| --- | ---: | ---: | ---: |
| STEP | 175 | 259 | 161 |
| CALL | 175 | 318 | 161 |
| DISPATCH | 175 | 307 | 161 |
| RELAY | 322 | 289 | 233 |
| CONTEXT | 423 | 489 | 228 |
| RECOVER | 180 | 314 | 156 |
| ANNOTATION | — | — | 161 |

Savings are constant over tested payload lengths 0, 1, 31, 32, 33, 256, and
4,096. Measurements include harness branching and can differ in other callers.
The baseline freezes the previous factories and decoders and uses the same
allocator and unchanged standalone writers. Input memory conversion and memory
poisoning occur before timing. Detailed results are written to
`.npm-cache/composite-results.json`.

Tests compare factory output with independent TypeScript encoders, poison the
future allocation, and verify zero trailing scratch/padding, the allocation
footprint, and an intact guard word. Decoder comparisons include nonzero starting
offsets, suffix bytes, wrong outer/child keys, malformed parent/child lengths,
truncation, and extreme absolute positions. Forged oversized factory inputs
verify identical `ValueOverflow` and arithmetic-overflow panic data before copying.

## LABEL and SCHEMA

LABEL and both SCHEMA factory overloads now use private allocated-buffer writers
to reuse their validated outer payload length. Their existing limits are retained:
these factories bound the outer payload to uint32, then allocate eight additional
bytes for its header. Standalone `writeLabel` and `writeSchema` are unchanged.

`unpackTailString` performs the packed header/remaining-length check for STRING
children. LABEL supplies the parent end directly. SCHEMA supplies the parent end
minus its trailing 32-byte name, validates the STRING, and reads the name at that
position. A too-short parent fails the helper's uint32 length check, including
when subtracting the name size underflows. String return types and their memory
copy remain unchanged.

Run `npx hardhat test test/string-composites.bench.test.ts`. Under the compiler
settings above, the measured additional execution gas savings are:

| Operation | Gas saved |
| --- | ---: |
| createLabel | 190 |
| createSchema, named and unnamed | 190 |
| unpackLabel | 156 |
| unpackSchema | 219 |

Savings are constant over tested input lengths 0, 1, 7, 8, 23, 24, 31, 32, 33,
256, and 4,096. Results include harness branching and are saved to
`.npm-cache/string-composite-results.json`. The prior BYTES composite benchmark
retains its factory and final-child savings; the leaf optimization below further
reduces RELAY and CONTEXT decoding.

Tests compare independent encoded bytes and decoded fields, named and unnamed
schemas, arbitrary non-UTF8 bytes, allocation guards, dirty memory, malformed
outer/child keys and lengths, every truncation point of sample blocks, extreme
absolute positions, and the exact oversized-input revert data. Frozen previous
implementations provide the decoding and gas baseline.

## Leaf decoders and fixed headers

`unpackList`, `unpackBytes`, and `unpackString` now add the header to the decoded
uint32 length without an overflow check, then perform one checked addition to
the absolute position. The bounded length plus eight fits uint256. This retains
the original arithmetic-overflow panic while avoiding a second checked addition.
The payload slice still contains the original length, and key validation still
occurs before the checked position arithmetic.

`enterFixed` and `enterEmpty` compare the packed 64-bit header against the
expected key and payload size. `enterFixed` remains private and only receives
fixed sizes 32 through 160. `enterEmpty` retains checked position arithmetic,
including the zero-key, out-of-calldata cases that can reach an overflow panic.

Run `npx hardhat test test/leaf-fixed.bench.test.ts`. Measured savings with the
compiler settings above, refreshed for 1.39.0, are 65 gas for each leaf decoder,
38 gas for each generic fixed-width decoder (`unpack32` through `unpack160`),
and 53 gas for `enterEmpty`.
Leaf savings are constant across lengths 0, 1, 31, 32, 33, 256, and 4,096.
Results include harness overhead and are written to
`.npm-cache/leaf-fixed-results.json`.

The composite baseline now also freezes its original BYTES and STRING leaf
implementations, preserving the historical comparison. RELAY and CONTEXT each
save another 72 gas in that harness because their first child uses `unpackBytes`;
the composite table above includes these additional savings.

Tests compare decoded values and exact revert data for wrong keys and sizes,
truncation, zero-padded reads, arbitrary spec ranges, zero/all-ones keys, and
extreme absolute positions. A separate bounds-only fixture checks payload
lengths through uint32.max without attempting to copy gigabytes of calldata.
