# Execute output preallocation experiment

These measurements predate composite Bootstrap. Its historical comparisons retain
the fixed Bootstrap layout; current behavior and gas are covered by
`bootstrap.test.ts` and `adapter-optimizations.bench.test.ts`.

Bootstrap and Debit know their final output size from fixed-stride input bounds.
The chosen exact-allocation path is now implemented in Execute and used
by both production adapters. The benchmark retains three experimental writers
and a frozen pre-adoption baseline. Encoder gains no specialized API.

All candidates retain the header/write32/write32 sequence and use the same
Execute decoding, hook order, funding and error logic:

- **Reserve once:** initialize a growable buffer, reserve the entire output,
  write using an absolute memory position, then finalize the written prefix.
- **Unchecked cursor:** initialize the current growable buffer, keep its packed
  cursor, and skip each write's capacity check because the loop proves capacity.
- **Exact allocation:** allocate the final bytes result, write using an absolute
  memory position, and return it without growable-buffer finalization.

The baseline inherits frozen adapters in PreviousExecuteOutput.sol. The Current
variant inherits actual production adapters. Current Debit now omits its former
operation log, so fresh gas comparisons also include that policy change.
Candidate adapter copies remain
in TestExecuteOutputPreallocation.sol. Identical hooks update observable
storage; an additional mode allocates memory inside every debit hook. The measured
region includes output allocation, all decoding/hooks/writes, and finalization.
Cursor construction and transaction intrinsic gas are excluded.

## Results

Solidity 0.8.35, viaIR, optimizer 200, Cancun. Positive values are gas saved.
These rows use nonallocating hooks, native Bootstrap with assigned value 100,
and non-native Debit with assigned value 100.

| Command / writer | Empty | 1 block | 2 blocks | 4 blocks |
|---|---:|---:|---:|---:|
| Bootstrap / reserve once | -204 | -77 | 50 | 304 |
| Bootstrap / unchecked cursor | -3 | 91 | 185 | 373 |
| Bootstrap / exact allocation | 35 | 162 | 289 | 543 |
| Debit / reserve once | -201 | -74 | 53 | 307 |
| Debit / unchecked cursor | 3 | 103 | 203 | 403 |
| Debit / exact allocation | 36 | 175 | 314 | 592 |

Exact allocation retains 32 fewer bytes, since no extra growable-writer scratch
word is needed. It won all tested cases, including empty output, allocating
hooks, chain/non-chain Bootstrap assets, zero/nonzero budgets, and 0/1/2/4/8/16
blocks. The benchmark asserts non-increasing gas for the exact candidate and
compares output bytes, credit and observable hook effects for every candidate.
Numbers can vary with host hooks and compiler inlining.

## Adopted implementation

Execute owns `allocateBalances(count)` and
`writeBalance(abs, asset, amount)`. The allocator composes Encoder.allocate
and pos; the writer composes writeHeader/write32/write32. Commands expose no
Encoder writer lifecycle and return the completed buffer directly.

The count must be bounded by uint32.max, as guaranteed by validated source
bounds. Its multiplication by 72 is then safe unchecked; the allocation primitive
rejects output sizes exceeding uint32.max. Unpackers and hooks retain their
existing order and funding semantics.

With those production helpers, the same focused harness measures:

| Command | Empty | 1 block | 2 blocks | 4 blocks |
|---|---:|---:|---:|---:|
| Bootstrap | 41 | 174 | 307 | 573 |
| Debit | 75 | 214 | 353 | 631 |

Both retain 32 fewer bytes and save gas in all tested cases. The count-based API
introduces a division for Debit, while validated bounds permit unchecked range
subtraction. Direct helper inlining also differs from the polymorphic prototype. These are the production results, distinct from the
prototype table above.

Encoder.allocate now documents when allocations may interleave writes:
all stores must remain within the retained rounded extent, and uninitialized
bytes must not be exposed. Execute.writeBalance stays entirely inside its
72-byte reserved logical block. Its hooks never receive the unfinished output.
Scratch writes beyond retained memory must still precede further allocations.

Focused behavior tests cover full-width quantities, unaligned final lengths,
interleaved hook allocations, later allocations, malformed streams, nonempty
state, hook failures, arithmetic overflow and validation error precedence.

```sh
npm test -- test/execute-output-preallocation.test.ts
npm run bench -- test/execute-output-preallocation.bench.test.ts
```

Results are written to `.npm-cache/execute-output-preallocation.json`.
