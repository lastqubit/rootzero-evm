# Execution and buffer optimizations

This pass covers execution traversal and decoding, raw source access, BALANCE
stream validation, output encoding, budget subtraction, and buffer reservation.
It keeps the existing allocation hint and growth policies and zero-initialization
semantics. Measurements use Solidity 0.8.35, optimizer runs 200, Cancun, without
viaIR. They include fixture branching and exclude transaction intrinsic gas;
inlining in other callers can change the savings.

## Traversal, raw sources, and budgets

`seekInput` is private and all callers calculate a forward position from a
uint32 cursor plus an eight-byte header and bounded payload. These calculations
cannot overflow uint256. The upper-bound check remains, while the redundant
backward-position check is removed. Cursor updates preserve the other lane,
end positions, and flags.

`rawState` and `rawInput` retain their explicit bounds checks and then construct
the calldata slice in assembly, avoiding Solidity's duplicate slice validation.
Their consuming variants set the current position to the already-validated end.
Undeclared lanes retain the original empty-return and non-consumption behavior.

`takeRawBalances` validates headers with a local cursor and commits the state
position once. Each iteration checks that a complete BALANCE remains before
checking its header. This preserves the old error order when a bad key precedes
a truncated tail. Empty or undeclared state returns before scanning or mutation.
The original calldata slice is returned without copying or re-encoding.

`unpack32` compares its fixed header as one packed value. It still takes the
complete input range before checking the header and uses only the spec's key.
`useValue` retains the insufficient-budget check and uses unchecked subtraction
only after that check proves it safe. Addition and final credit checks remain.

Run `npx hardhat test test/execution-optimization.bench.test.ts`.

| Operation | Execution gas saved |
| --- | ---: |
| Dynamic decoding, consume, tryConsumeEmpty | 32 per call |
| rawState / rawInput | 102 |
| takeRawState | 266 |
| takeRawInput | 257 |
| unpack32 | 67 |
| useValue | 66 |
| takeRawBalances, empty | 106 |
| takeRawBalances, 1 block | 708 |
| takeRawBalances, 8 blocks | 6,532 |
| takeRawBalances, 64 blocks | 53,124 |
| takeRawBalances, 256 blocks | 212,868 |

Tests compare complete cursor words, remaining budgets, returned values, and
exact revert data. Cases cover absent/declared lanes, reserved high bits,
inverted and out-of-calldata bounds, truncated headers, malformed block order,
and zero/maximum budgets. Results: `.npm-cache/execution-results.json`.

## Reusing reserved output sizes

Execution output helpers already compute a complete block size and reserve it.
New internal `Blocks.*Sized` writers accept that size rather than calculating
it again. They support a nonzero write offset; factory-only allocated writers
cannot be reused because an execution buffer's capacity is not its block size.
Generic calldata output uses `copySized` after reservation has proved its length
fits the buffer's uint32 capacity. The original standalone writers and factory
implementations remain intact.

These helpers are unchecked writers: callers must pass the exact size for the
payloads and reserve the full destination plus trailing header scratch space.
Execution helpers preserve their existing arithmetic and reservation before
calling them, including rejection of oversized inputs before copying.

Run `npx hardhat test test/execution-output-optimization.bench.test.ts`.

| Layout | Memory output saved per block | Calldata output saved per block |
| --- | ---: | ---: |
| STEP | 129 | 186 |
| CALL | 129 | 245 |
| DISPATCH | 129 | 245 |
| RELAY | 246 | 228 |
| CONTEXT | 321 | 399 |
| RECOVER | 146 | 203 |
| LABEL | 146 | — |
| SCHEMA | 146 | — |
| Generic block | — | 57 |
| LIST | — | 89 |
| BYTES / STRING | — | 118 |

The matrix covers lengths 0, 1, 31, 32, 33, 256, and 4,096; one and eight
appends; growing and preallocated buffers; and nonzero output offsets. Tests
compare independent encoded bytes and memory footprints. Additional cases cover
empty first/second children and forged oversized lengths. Results:
`.npm-cache/execution-output-results.json`.

The execution baseline freezes the original execution helpers but shares current
Blocks decoders and Buffers with the optimized branch. These comparisons isolate
execution changes; the buffer savings below are measured separately.

## Buffer growth and initialization

`Buffers.reserve` removes three sets of redundant arithmetic checks:

- Its initial capacity is uint32, so the first doubling cannot overflow uint256.
  Later growth-loop multiplications remain checked, preserving panic behavior
  for extreme requested sizes.
- After growth, `required >= position + advance` and
  `required <= capacity <= uint32.max`. Updating the packed cursor cannot carry
  out of its position lane, including when reserved high bits are set.
- Padding calculations for lazy allocation use that validated uint32 capacity
  and cannot overflow uint256.

The required-size addition, growth limit, physical backing check, standalone
allocation/resize checks, and zero filling remain unchanged. General buffer
reservation does not promise that callers overwrite every reserved byte, so
the factory optimization of skipping most zero initialization is not applicable.
The existing allocation-policy benchmarks show workload-dependent tradeoffs;
this pass keeps the current hints, fallback scan, and geometric growth policy.

Run `npx hardhat test test/buffer-reserve-optimization.bench.test.ts`.
The tested reserve paths save 56–278 execution gas. These savings also benefit
the shared Writer helpers. Tests poison future memory and compare the entire
backing buffer, copied prefix, zero-filled suffix, cursor, write position, and
allocation footprint. Adversarial cases compare exact errors for extreme
sizes, inconsistent backing buffers, and packed cursors with high bits set.
Results: `.npm-cache/buffer-reserve-results.json`.
