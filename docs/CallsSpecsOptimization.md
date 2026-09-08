# Calls returndata and specification sizes

Benchmarks use Solidity 0.8.35, optimizer runs 200, Cancun, without viaIR.
They compare frozen previous implementations in a shared fixture. Gas includes
fixture branching and target execution, excluding transaction intrinsic gas.
Compiler inlining and caller memory usage can change these results.

| Operation | Gas saved, single operation | Allocation saved |
| --- | ---: | ---: |
| Successful `rawCall` | 33 | 32 bytes |
| Successful `rawCallCopy` | 33 | 32 bytes |
| Successful `rawQuery` | 28 | 32 bytes |
| `Specs.blockSize`, nonzero key | 56 | none |
| `Specs.allocation`, nonzero key | 67 | none |

Eight successful calls save 286-317 gas for rawCall/rawCallCopy and 246-277 gas
for rawQuery, depending on payload size, with 256 fewer allocated bytes.
Smaller allocations also reduce subsequent memory expansion costs.
These measurements include the expectEmpty correctness fix described below,
which adds 6 gas per rawCall/rawCallCopy relative to the initial layout change.

There are small measured tradeoffs: target failures cost 7 additional gas in the
outer catch fixture. A zero-key blockSize costs 10 additional gas in its fixture;
zero-key allocation saves 1 gas. These figures include old/new branch and
compiler-layout differences, rather than isolating individual EVM instructions.

## Implementation and invariants

Successful ABI returndata already contains a length word for its bytes payload.
Calls now copies it directly into the free memory region, validates it, and
returns a pointer to that length word. It no longer adds a separate bytes wrapper
around the entire successful ABI response. Validated total size is word-aligned,
so the free memory pointer advances by exactly that size.

The failure path still constructs a bytes wrapper and raises FailedCall with the
original target, selector, and exact revert data. Successful responses retain
the same offset, length, padding-size, and trailing-data checks. Nonzero padding
bytes remain accepted. Input encoding and the try-call helpers are unchanged.

Specs.blockSize retains its zero-key special case and reads a uint24 hint.
Adding the eight-byte header cannot overflow uint256. Only that addition becomes
unchecked; allocation's multiplication remains checked.

## Verification

Run `npx hardhat test test/calls-specs-optimization.bench.test.ts`.

Calls tests cover memory/calldata input and static queries, one/eight calls,
outputs of 0/1/2/31/32/33/256/4096 bytes, retained first/last results, and an
overwrite of the next allocation to detect insufficient output reservation.
They compare truncated headers, invalid offsets, oversized lengths, incorrect
padding sizes, trailing data, dirty padding, native-value forwarding, and exact
FailedCall bytes. Failure gas is measured separately through an outer catch.

Specs tests compare independently computed sizes across zero/nonzero keys,
uint24 boundary hints, reserved bits, repeated calls, and allocation counts at
the uint256 multiplication boundary, including exact arithmetic panic data.

Results are written to `.npm-cache/calls-layout-results.json`,
`.npm-cache/calls-failure-results.json`, and `.npm-cache/specs-size-results.json`.

## Subsequent expectEmpty correctness fix

The previous `and(expectEmpty, outputLen)` condition was a bitwise AND, so a true
expectEmpty rejected odd output lengths but accepted even nonzero lengths.
rawCall and rawCallCopy now normalize outputLen to a boolean before combining
it with expectEmpty. Both reject every nonempty output with the existing empty
revert data; zero-length outputs and calls without expectEmpty retain their
behavior. The frozen baseline remains unchanged. Differential tests account for
this intentional correction, and dedicated regressions exercise both input modes
with lengths 0/1/2/3/31/32/33/64/256.
