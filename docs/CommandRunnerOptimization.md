# Shared command-runner optimization

These measurements predate the subsequent text-unpacker fix. That fix makes
STRING/LABEL/SCHEMA adapters check bounds before copying and addresses the
SCHEMA viaIR failure recorded below; the results here remain the original
runner-only comparison.

Measured on 2026-09-24 with Solidity 0.8.33, viaIR enabled, optimizer 200.
The upstream build retains its Cancun target; the isolated commander integration
build retains its Osaka target. Each baseline/candidate pair uses the same target,
compiler settings, deployment sequence, and test order.

`hardhat.runner.config.ts` selects the requested measurement settings without
changing the default Solidity 0.8.35/non-viaIR configuration.

The baseline is the current worktree before either shared runner change, including
the existing Position, Balance, Bootstrap, and Pipeline optimizations. This is not
a comparison against an otherwise unmodified 1.44.1 release. The candidate changes
only `Executions.openContext` and the capacity multiplication in `writerCursor`.

## Implementation

`openContext` now reads the CONTEXT header, account, and nested BYTES headers and
packs both cursor lanes in one memory-safe assembly block. Validation remains in
the same order: CONTEXT key, state BYTES key, input BYTES key/exact length, then
outer context boundary. Underflow in the tail length is rejected by its uint32
bound. Offset additions combine a bounded calldata offset with uint32 lengths;
they cannot overflow uint256. The generic absolute-offset `Blocks.unpackContext`
API is unchanged.

Both writer counting paths produce at most uint32.max items. Multiplication by a
uint32 output block size therefore fits uint64. Only this multiplication loses
its redundant Solidity overflow check; `Buffers.cursor` retains its uint32
capacity guard, and buffer allocation and growth remain checked.

## Measurements

Savings are per runner invocation, not per batch item. The synthetic harness
covers output-free, state-only, input-only, and paired callbacks at batch sizes
0, 1, 4, 16, and 64, checking exact output and unused credit in every case.

| Host workload | Baseline gas | Candidate gas | Saved |
| --- | ---: | ---: | ---: |
| State-only, 1 item | 25,634 | 25,415 | 219 |
| State-only, 16 items | 42,912 | 42,693 | 219 |
| Input-only, 16 items | 42,598 | 42,379 | 219 |
| Paired, 16 items | 53,934 | 53,715 | 219 |
| Output-free, 1 item | 24,387 | 24,219 | 168 |
| Position/settle/withdraw pipeline | 66,796 | 66,565 | 231 |
| Local position-check pipeline, 1 position | 51,536 | 51,311 | 225 |
| Separate position-check pipeline, 15 positions | 217,246 | 217,021 | 225 |

Output-free batches of 4/16/64 and the paired batch of 64 hit the calldata gas
floor and show no receipt savings. Their receipts equal the calculated floors
of 27,080 / 38,240 / 82,850 / 142,430 gas, respectively. The position-check pipeline saves 225 gas in
both variants at every measured batch size (1, 2, 4, 8, 15). Pipelines that do not
use the shared context runner show no savings.

| Contract (host build) | Runtime before | Runtime after | Change | Initcode change |
| --- | ---: | ---: | ---: | ---: |
| CommandRunnerBenchmark | 2,607 | 2,570 | -37 bytes | -37 bytes |
| PositionCommand | 1,931 | 1,879 | -52 bytes | -52 bytes |
| Main | 12,038 | 12,095 | +57 bytes | +57 bytes |

Bytecode effects depend on composition and compiler code sharing; gas savings
do not imply every host becomes smaller. Raw measurements are recorded in
`CommandRunnerOptimization.json`.

The upstream Cancun build produces the same 20 runner gas rows, differential
digest, and benchmark bytecode sizes as the host's Osaka build.

## Reproduction and validation

Run the same benchmark command before and after the two helper edits, preserving
the harness and configuration:

```sh
npm run bench -- test/command-runner.bench.test.ts test/command-context-differential.test.ts --config hardhat.runner.config.ts
npm test -- --config hardhat.runner.config.ts
npm run typecheck
npm test
```

The differential corpus hashes 331 exact ABI-encoded success/output/credit or
failure/revert outcomes. Its baseline digest is asserted by the permanent test:
`0x07a54e4b915a07b3a309a9399c2b20f81f1ae3d21a69c64dbf1a3253ee73b7c3`.
Cases include truncated headers/payloads, wrong keys, inconsistent nested lengths,
uint32 maximum lengths, trailing bytes, additional contexts, and once-only source
consumption. Direct tests also check account, cursor bounds, declared lane flags,
full-width budget, and both capacity-counting paths at the uint32 capacity limit.

Host comparisons run `CommandRunnerGas.ts`, `PipelineGas.ts`,
`PositionCheckGas.ts`, and `CommandContextDifferential.ts` in that order in fresh
Hardhat processes. The isolated dependency is refreshed from this worktree; the
neighboring checkout is not modified. The full host suite passes 181 tests,
including parser/pipeline fuzzing, refunds, authorization, handoffs, and rollback.

The full upstream run under 0.8.33/viaIR reports **1,260 passing and one existing
failure**: `blocks.test.ts`, "rejects schema truncation, invalid child headers,
and the former trailing name word". A SCHEMA truncated to 48 bytes reverts with
empty data instead of the asserted `OutOfBounds`. Recompiling and deploying the
fixture with the original runner source produces identical executable bytecode
(1,839 runtime bytes) and identical revert bytes at every truncation length.
This compiler-specific baseline behavior is outside the two runner changes;
the decoder and its expectation are unchanged.

The required default-compiler verification passes: `npm run typecheck` and all
**1,261 upstream tests**. The focused viaIR benchmark/differential run passes
both tests, covering 20 benchmark rows and 331 differential cases.

## Release 1.45.0 verification

After the text-unpacker fix and shared constant refactors, `npm run test:all`
passes all 1,344 tests, including benchmarks, under the default Solidity 0.8.35
configuration. TypeScript checking also passes. An additional 52 focused tests
covering text bounds, context decoding, check commands, bootstrap, and pipeline
parsing/budgets pass under Solidity 0.8.33 with viaIR and optimizer 200 runs.
The SCHEMA revert-data failure recorded in the original comparison is fixed.
