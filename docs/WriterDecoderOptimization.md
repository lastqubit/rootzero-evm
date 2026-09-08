# Writers, Decoders, and Budgets

These changes extend the execution optimizations to the standalone libraries.
Measurements use Solidity 0.8.35, optimizer runs 200, Cancun, without viaIR.
They compare frozen previous implementations in the same fixtures. Gas includes
fixture branching and excludes transaction intrinsic/calldata gas; results can
differ when inlined into other callers.

## Writers

Generic memory append and calldata copy helpers reuse their validated payload
length. Composite append/copy helpers pass their reserved complete block size to
the existing `Blocks.*Sized` writers. This avoids recalculating lengths or
repeating their uint32 validation. The existing schema checks, checked size
arithmetic, and buffer reservation remain in their original order.

`Blocks.writeSized` is now internal so generic memory append can use it. Its
preconditions match the calldata helper: the supplied payload length must be
exact and fit uint32, and the caller must reserve the header, payload, and
trailing scratch space. Original standalone writer bodies and allocation
policies are unchanged.

Run `npx hardhat test test/writer-optimization.bench.test.ts`.

| Layout | Memory append saved per block | Calldata copy saved per block |
| --- | ---: | ---: |
| Generic block | 57 | 57 |
| STEP | 129 | 186 |
| CALL / DISPATCH | 129 | 245 |
| RELAY | 246 | 228 |
| CONTEXT | 321 | 399 |
| RECOVER | 146 | 203 |
| LABEL / SCHEMA | 146 | — |
| LIST | — | 89 |
| BYTES / STRING | — | 118 |

The matrix covers all 19 changed helpers, payload lengths 0, 1, 31, 32, 33,
256, and 4,096, one/eight appends, growing/preallocated buffers, and nonzero
write offsets. Savings are constant per block across that matrix. Tests compare
independently encoded output and allocation footprints, then check asymmetric
empty children and exact rejection of forged oversized payloads. Both branches
share current Buffers, isolating the Writer changes. Results:
`.npm-cache/writer-results.json`.

## Decoders

A private `seekAfterBlock` helper is used only after successful block decoding
or empty-header validation. These paths derive a forward position from a uint32
cursor plus bounded block lengths. It retains the upper-bound check and all
cursor metadata, while removing the redundant backward-position check.
General-purpose `Cursors.seek` still checks both directions.

`unpack32` now compares the packed key/length header. It still consumes the
fixed-size range before validating the header and uses only the spec's key,
preserving its previous behavior and error precedence.

Run `npx hardhat test test/decoder-optimization.bench.test.ts`.
Dynamic decoders, both consume overloads, and `tryConsumeEmpty` save 24 gas per
call. `unpack32` saves 67 gas per call. Both one-call and eight-call batches are
measured. Tests compare returned values, full cursor words, exact errors,
truncated/wrong headers, partial input, forged bounds, and reserved high bits.
Results: `.npm-cache/decoder-results.json`.

## Budgets

Both `useValue` overloads retain their explicit insufficient-funds check and
perform unchecked subtraction only afterward. Resource deductions still extract
the low 128-bit EVM value lane before calling these helpers. Budget additions
remain checked.

Run `npx hardhat test test/budget-optimization.bench.test.ts`.

| Operation | Execution gas saved |
| --- | ---: |
| Memory budget, direct value | 104 |
| Scalar budget, direct value | 87 |
| Memory budget, resource lane | 104 |
| Scalar budget, resource lane | 66 |

Tests verify independently calculated balances and consumed amounts for zero,
exact, insufficient, uint128-boundary, and uint256-maximum values, including
nonzero upper resource bits. Failures retain `InsufficientValue` exactly.
Results: `.npm-cache/budget-results.json`.
