# Calls returndata and specification sizes

Benchmarks use Solidity 0.8.35, optimizer runs 200, Cancun, without viaIR.
They compare frozen previous implementations in a shared fixture. Gas includes
fixture branching and target execution, excluding transaction intrinsic gas.
Compiler inlining and caller memory usage can change these results. Results below
were refreshed on 2026-09-11 after the port return-tuple migration. Current calls
decode `(bytes, uint)` while the frozen baseline decodes `bytes`; query results
remain bytes-only. This comparison includes the ABI change, not just decoder costs.

| Operation | Gas saved, single operation | Allocation saved |
| --- | ---: | ---: |
| Successful `rawCall` | -9 to -11 | 0 bytes |
| Successful `rawCallCopy` | -9 to -11 | 0 bytes |
| Successful `rawQuery` | 28 | 32 bytes |
| `Specs.blockSize`, nonzero key | 56 | none |
| `Specs.allocation`, nonzero key | 67 | none |

Negative savings mean additional gas. Eight successful rawCall/rawCallCopy calls
cost 51-61 extra gas and save no allocation against the bytes-only baseline.
Eight rawQuery calls save 246-277 gas and 256 allocated bytes, depending on payload
size. These measurements include the expectEmpty correctness fix described below.

Target failures cost 9 additional gas for rawCall/rawCallCopy and 7 for rawQuery
in the outer catch fixture. A zero-key blockSize costs 10 additional gas in its fixture;
zero-key allocation saves 1 gas. These figures include old/new branch and
compiler-layout differences, rather than isolating individual EVM instructions.

## Implementation and invariants

Successful ABI returndata already contains a length word for its bytes payload.
Each helper copies it directly into the free memory region, validates it, and
returns a pointer to that length word. It no longer adds a separate bytes wrapper
around the entire successful ABI response. Validated total size is word-aligned,
so the free memory pointer advances by exactly that size.

The failure path still constructs a bytes wrapper and raises FailedCall with the
original target, selector, and exact revert data. Successful responses retain
length, padding-size, and trailing-data checks. Calls require a 64-byte dynamic
offset and a 96-byte minimum tuple response; queries retain a 32-byte offset
and a 64-byte minimum response. Nonzero padding
bytes remain accepted. Input encoding and the try-call helpers are unchanged.

Specs.blockSize retains its zero-key special case and reads a uint24 hint.
Adding the eight-byte header cannot overflow uint256. Only that addition becomes
unchecked; allocation's multiplication remains checked.

## Verification

Run `npm run bench -- test/calls-specs-optimization.bench.test.ts`.

Calls tests cover memory/calldata input and static queries, one/eight calls,
outputs of 0/1/2/31/32/33/256/4096 bytes, retained first/last results, and an
overwrite of the next allocation to detect insufficient output reservation.
Call fixtures adapt the frozen bytes-only response to the tuple ABI by inserting
a zero credit word and adjusting the offset. Query and revert fixtures are unchanged.
Tests compare truncated headers, invalid offsets, oversized lengths, incorrect
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
