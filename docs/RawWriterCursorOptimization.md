# Raw writers and cursor navigation

Measurements compare frozen previous helper implementations in the same fixture,
using Solidity 0.8.35, optimizer runs 200, Cancun, without viaIR. Gas includes
fixture branching and excludes transaction intrinsic/calldata gas. Savings may
differ when the compiler inlines these helpers into other callers.

| Helper | Gas saved per call |
| --- | ---: |
| `Cursors.advance` | 69 |
| `Cursors.consume` | 74 |
| `Writers.append` | 156 |
| `Writers.copy` | 152 |
| `Writers.append32` | 129 |
| `Writers.append64` | 131 |
| `Writers.append96` | 124 |

## Bounds and behavior

Cursor navigation still checks `amount <= end - position`, including checked
subtraction for inverted ranges. This proves the resulting position fits uint32,
so adding `amount` to the packed cursor cannot carry into its metadata or overflow
uint256. Only this final addition becomes unchecked. All reserved high bits and
the distinction between `OutOfBounds` and arithmetic panic are preserved.

Raw writers reserve the maximum of their logical advance and physical write
size before copying/storing directly. Reservation already checks arithmetic,
capacity growth, and the destination's physical length. The removed checks in
`Buffers.write*` and `Buffers.copy` repeated those guarantees. Standalone Buffers
helpers retain their checks. Both benchmark branches share current Buffers,
isolating the raw writer changes.

Word appends still write all 32/64/96 bytes, including the tail beyond `keep`.
Existing behavior for `keep = 0` and values above 32 remains unchanged, as do
checked additions for `32 + keep` and `64 + keep`. Allocation and zero
initialization are unchanged.

## Verification

Run `npx hardhat test test/raw-writer-cursor-optimization.bench.test.ts`.

The writer matrix covers all five helpers, capacities 0/64/4096, one/eight
writes, nonzero starting offsets, and lengths/keep values 0/1/31/32/33/256.
Tests compare full physical buffers against both the baseline and independently
constructed expected bytes, plus packed cursors and allocation footprints.
Additional cases compare aliased memory sources across growth and exact errors
for oversized/overflowing keep values. Results are written to
`.npm-cache/raw-writer-results.json`; savings are constant per call in this matrix.

Cursor tests exercise one/eight/32 operations, arbitrary high metadata bits,
zero advances, exact endpoints, uint32 boundaries, inverted ranges, and
uint256-maximum inputs. They compare complete cursor words, consumed positions,
and exact revert data.
