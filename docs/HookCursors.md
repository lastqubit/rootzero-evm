# Internal hook cursors

> Historical experiment suites referenced below have been retired. Recorded
> measurements are retained; see [the current core benchmarks](../README.md#development)
> for the supported benchmark commands.

Pass calldata-backed payloads through internal hooks as uint cursors. The low
32 bits hold the absolute position and the next 32 bits hold the exclusive end.
The caller establishes provenance and logical bounds; the hook decodes or forwards
that bounded range. Cursors refer to the current call's calldata, not another
contract's calldata, and do not replace external ABI bytes arguments.

| Hook | Calldata cursor argument | Memory arguments retained |
|---|---|---|
| RelayPayableHook.relay | inputCur | context, funds |
| RecoverPayableHook.recover | witnessCur | funds |
| PipeHook.pipe | stepsCur | state |
| ExecuteHook.execute | inputCur | state; output return value |
| ForwardHook.forward | messageCur | none |
| DispatchPayableHook.dispatchTo | payloadCur | funds |

These are breaking internal signatures. Overrides should receive the cursor
directly and use CursorBlocks to decode it. Convert with toBytes only when an
operation needs bytes, such as event encoding. Blocks.hash and the Calls
cursor overloads consume the range directly.
Calling another internal hook does not itself require conversion.

Dispatch's port payload originates in calldata, so its hook no longer forces
an intermediate memory copy. A genuinely memory-backed value should remain
bytes memory: Relay's newly encoded context and Pipeline's threaded state/output
are deliberately unchanged. Pipe still materializes its initial state because
the pipeline owns and threads a memory buffer across local and external commands.

Portal.resolve accepts and returns a witness cursor. Portal hashes and forwards
these cursors directly. External transport entrypoints construct a cursor once
with Cursors.wrap. Calls.tryRaw and Calls.raw now overload their memory versions
with uint dataCur; Executions.rawCall follows the same pattern. The calldata
Copy variants are removed. These helpers trust validated calldata bounds, ignore
metadata, and do not advance the cursor. The ABI call buffer receives a single
calldata copy. Blocks.hash likewise copies into temporary free memory for
KECCAK256, without allocating bytes or advancing the free-memory pointer.

Pipeline carries independent STEP-stream and command-input cursors. Both use
standard start/end lanes. takeStep returns cmd, value, inputCur, and nextCur;
the local execute hook receives inputCur directly. The external-call encoder
receives inputCur and the continuation separately, deriving lengths when copying.
Ordinary calls use zero for the continuation; handoffs pass the actual stream
cursor, which remains nonzero even when its remaining range is empty.

Execute adapters now accept inputCur instead of calldata bytes. The existing
fixed-stride command loops retain their one-time divisibility validation and
error ordering. Execute.bounds(cur, size) exposes already validated source
bounds without converting to a calldata slice. Memory streams use the bytes
overload. The specialized unpackers avoid per-block containment checks.
CheckBalance/CheckPosition delegate their fused loops to Execute; see
[Execute.md](Execute.md) for the API and benchmark.

## Verification and gas

Separating the two Pipeline cursors compiles with viaIR without stack-depth
errors. Against the frozen packed-input implementation, internal gas savings are:

| Flow | 1 step | 4 steps | 16 steps |
|---|---:|---:|---:|
| Local execution | 31 | 106 | 406 |
| External execution | 49 | 178 | 694 |

Empty pipelines save 6 gas. A handoff saves 33 gas with 0, 1, or 4 continuation
steps. The comparison covers empty and non-empty command inputs and asserts no
gas regression. Tests compare the exact forwarded RELAY payload and prove that
continuation steps are not executed locally, including terminal handoffs.

Run `npm run bench -- test/pipeline-cursors.bench.test.ts`. The packed baseline
is kept in contracts/test/PreviousPackedPipeline.sol. These are internal gasleft
measurements with identical observable command work, not transaction intrinsic
gas. State remains bytes memory; only calldata ranges are cursors.

### Earlier hook-signature comparison

Existing command, recovery, portal, dispatch, pipeline, and execute-adapter tests
exercise the new signatures through unchanged external ABI entrypoints.

A snapshot comparison of the first hook migration (before separating Pipeline's
input cursor) used the pre-hook-migration ABI/bytecode for
TestPipelineOptimization and TestAdapterOptimizations, deployed alongside the
current fixtures. Both builds use Solidity 0.8.35, viaIR, optimizer 200, Cancun.
Measurements exclude external ABI encoding and transaction intrinsic gas.

| Path | New minus old internal gas |
|---|---:|
| Empty pipeline | +3 |
| Local pipeline, 1-16 steps | +3 per invocation |
| External pipeline, 1 step | -41 |
| External pipeline, 4 steps | -173 |
| Direct CheckBalance adapter fixture | +45 per invocation |
| Direct Bootstrap adapter fixture | +39 per invocation |
| Direct Bootstrap + CheckBalance fixture | +90 per invocation |

The adapter fixtures still take external bytes and now construct cursors inside
the measured region; real pipeline hooks already receive a cursor. These are
boundary costs, not growing per-block decoder costs. The initial hook migration is an API
consistency change, not a claim that every call site saves gas. The earlier
offset/length-to-cursor conversion added per-step overhead and was removed by
using start/end lanes throughout Pipeline.

Snapshot artifacts and results are in .npm-cache/cursor-hooks-baseline and
.npm-cache/cursor-hooks-comparison.json for this session. The regular
pipeline-optimization and adapter-optimizations benchmarks continue to measure
the maintained production paths without requiring those snapshots.

Cursor hash and length primitives are covered by `test/cursor-hash.test.ts` and
`test/cursor-hash.bench.test.ts`. Under solc 0.8.35, viaIR, optimizer 200,
`length(cur)` has identical executable runtime bytecode to the inline unchecked
subtraction. Scratch hashing saves 214-221 internal gas against
`keccak256(Blocks.toBytes(cur))` in the focused harness across 0-4096 bytes.
It still copies calldata, as KECCAK256 operates on memory; the saving removes
bytes allocation and its bookkeeping, not the copy itself.
