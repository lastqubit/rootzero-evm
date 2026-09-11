# Shared versus direct enter validation

Historical report: `Executions.enterNext` has since been removed in favor of
separate `more` and `enter` calls. Combined-entry implementations remain only in
benchmark fixtures. The measurements below predate that removal; rerunning the
benchmarks compares the current separate loop against the frozen implementations.

The shared validation improvement is now adopted in production Blocks.enter.
Executions and Decoders retain their wrappers. enterNext now also delegates to
Blocks.enter to centralize validation, accepting its measured gas and bytecode
cost versus the earlier inline implementation. Direct alternatives remain test-only.

Blocks.enter replaces its Specs.matches call with equivalent key/min/max checks
inside the spec-based overload. Execution and Decoder wrappers retain their
current structure and call the production shared helper. PreviousEnter.sol freezes
the old validation and wrappers for comparison. The direct alternative puts header
decoding, validation, position calculation, and cursor mutation directly in each
Execution/Decoder overload. Both preserve prefix checks and error ordering.

## Normal enter helpers

Solidity 0.8.35, optimizer runs 200, Cancun, without viaIR. Separate contracts
share a harness and identical external interfaces. Gas measures traversal and
entry, excluding transaction intrinsic gas and execution initialization.

| Overload | Shared validation: gas saved per entry | Direct implementation: gas saved per entry |
| --- | ---: | ---: |
| Spec, header only | 78 | 128 |
| Key, header only | 0 | 57 |
| Spec, fixed prefix | 78 | 198 |
| Key, fixed prefix | 0 | 127 |

Results are the same for Executions and Decoders. Savings are linear across
one and 32 parents. Both a loop using the returned body/end and a fixed-layout
loop discarding those results produce the same savings. The prefix used in the
timed matrix is 104 bytes inside a 208-byte parent.

These measurements establish that normal entry still has avoidable overhead.
The shared change benefits spec-based callers without duplicating validation in
each wrapper. Direct implementations save another 50 gas on spec header entry
and 120 gas on spec prefix entry, plus savings on key-based entry.

## Shorter enterNext with improved shared validation

The measurements below were captured before adopting the shorter enterNext.
The additional fixture checked whether the shared change closes the gap between
the short and current inline enterNext implementations. It uses the same two
ACCOUNT_AMOUNT child decoding pattern as the earlier enterNext benchmark.

| Parents | Original more/enter | Current inline enterNext | Shorter improved-shared enterNext |
| ---: | ---: | ---: | ---: |
| 0 | 219 | 276 | 276 |
| 1 | 2,341 | 2,196 | 2,273 |
| 8 | 17,195 | 15,636 | 16,252 |
| 32 | 68,123 | 61,716 | 64,180 |
| 128 | 271,835 | 246,036 | 255,892 |

The improved-shared version saves `125 * parents - 57` against the original
loop but costs 77 gas per parent more than current inline enterNext. The shared
change helps but does not make the implementations equally cheap. Actual
integration savings depend on compiler inlining and surrounding code.

## Verification

Run:

```
npx hardhat test test/shared-enter.bench.test.ts test/shared-enter-next.bench.test.ts
```

Normal-enter differential tests compare all four overloads in both libraries,
including returned bounds, metadata preservation, truncated input, wrong keys,
wrong lengths, unbounded maximum specs, empty payloads, exact-end prefixes,
oversized prefixes, and uint256-maximum amounts. Error comparisons use exact
revert data. The enterNext fixture also explicitly checks that unread state
prevents silent completion when input is exhausted.

Results: `.npm-cache/shared-enter-results.json` and
`.npm-cache/shared-enter-next-results.json`. TypeScript checking also passes.

## Deployed bytecode size

Runtime bytecode measurements include compiler metadata, excluding constructor
code and constructor arguments. Baseline recompilation matches existing artifact
sizes. Four variants were compiled from the same current source tree and compiler
settings using standard JSON input; alternatives were applied only in memory.
Production source files and Hardhat artifacts were not overwritten.

| Contract | Pre-change bytes | Shared validation delta | Direct normal-enter delta | Shared validation + shorter enterNext delta |
| --- | ---: | ---: | ---: | ---: |
| TestEnterCurrent (all Execution overloads) | 2,752 | -41 | +211 | -41 |
| TestDecoderEnterCurrent (all Decoder overloads) | 1,769 | -41 | +199 | -41 |
| TestHost (composed integration fixture) | 20,281 | -38 | 0 | -38 |
| TestExchange | 2,206 | 0 | 0 | +30 |

The direct variant changes the eight normal enter overloads but leaves Blocks
and enterNext alone. Its zero integration deltas mean these particular fixtures
have no emitted-code size change from that alternative; they do not establish
that direct entry is size-neutral for contracts that use those overloads.

Standalone enterNext fixture runtime sizes:

| Implementation | Bytes |
| --- | ---: |
| Original more/enter loop | 1,478 |
| Current inline enterNext | 1,367 |
| Short enterNext using current Blocks.enter | 1,438 |
| Short enterNext using improved shared validation | 1,378 |

The results favor improving shared Blocks.enter validation: it saves 78 gas on
spec entry and reduces emitted size in the measured users. Direct normal-entry
implementations offer extra runtime savings at a size cost in the all-overload
fixtures. The shorter shared enterNext is slower and larger in both its isolated
fixture and TestExchange, but is now adopted to centralize validation because
this helper is expected to be used infrequently. The previous inline version is
retained for differential benchmarks.

Raw sizes: `.npm-cache/enter-bytecode-results.json`. The isolated standard-JSON
compiler outputs are retained as `.npm-cache/enter-size-*.json`.
