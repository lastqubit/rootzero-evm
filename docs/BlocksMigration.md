# Historical Blocks caller migration benchmark

Current execution cursors no longer carry lane flags. Whole-stream selectors trust
calldata bounds established during opening and validate block structure without
repeating provenance checks. The lane/provenance checks and measurements below
describe the earlier migration baseline.

Migration is complete: the cursor implementation is now `Blocks`, while the old
Blocks and Memory APIs survive only as explicitly named test baselines.

The cursor-loop experiments below are historical. The production execute
adapters now use the specialized [Execute](Execute.md) library,
preserving their once-per-stream validation and absolute iteration. That migration
matches prior gas except Settle, which saves 96 gas per POSITION in its benchmark.
The old memory-cursor proposal is frozen as PreviousMemoryBlocks under test/.

## Scope and method

The measured counting, relay, and annotation improvements are now implemented.
At the time of this experiment the codec libraries were unchanged. The six
execute-loop migrations below were benchmark-only. Decoders and Writers have
since been removed; current callers use Blocks and Encoder.
The benchmark fixture copies the six pre-hook-migration execute method bodies, substitutes
cursor construction/unpacking/advancement in separate candidate contracts, and
uses identical observable storage hooks. Bootstrap retains its actual funding
logic; Debit and Bootstrap retain their real Encoder output writes.

Solidity 0.8.35, viaIR, optimizer 200, Cancun. Numbers below are measured inside
the wrappers with `gasleft`, excluding ABI decoding/encoding and transaction
intrinsic gas. They are controlled caller-body comparisons, not guarantees for
every host subclass: different hooks and inlining can change results. All valid
cases compare output bytes, returned credit, handled status, and hook checksum.

The standalone encoder/count comparisons begin with already packed calldata
cursors, as real relay callers do. Migrated annotation benchmarks call the actual
Encoder creators. Action and Counterparty now use Encoder creators as well; their small
measured overhead is accepted.
The baseline relay balance helper is frozen in the fixture so library changes
cannot accidentally change both sides of the comparison.

## Execute loops

Positive delta means the new cursor path costs more gas.

| Caller | 1 block | 2 blocks | 4 blocks |
|---|---:|---:|---:|
| CreditAccount | +175 | +256 | +418 |
| Cashout | +172 | +250 | +406 |
| Settle | +378 | +658 | +1219 |
| DebitAccount | +39 | +81 | +165 |
| Bootstrap | +7 | +35 | +91 |
| Authorize | +67 | +139 | +283 |
| Bootstrap(chain,budget=0) | +7 | +35 | +91 |
| Bootstrap(chain,budget=100) | +7 | +35 | +91 |

All six non-empty execute candidates regress in this compilation. The old loops
validate fixed-stride divisibility once, then read headers/payloads and advance an
absolute pointer. New unpackers enforce containment per block and return packed
cursors. The memory constructor also checks representable absolute bounds.
Those are different validation strategies; the old decoder is not performing
the same per-block work. Settle has the largest regression and needs separate
inspection of the struct/unpacker compilation before migration.

## Counting and encoding

| Path | New minus old gas |
|---|---:|
| runCount, 0-16 matching blocks | 0 |
| Relay context creation from payload cursors | -39 |
| Relay balance validation + consumption + context creation, non-empty | -64 |
| Same relay path, empty state | 0 |
| Label / Schema Wrap creators, 0-1024 text bytes | -46 |
| Groups Wrap creator, 0-1024 text bytes | -235 to -439 |
| Action creator | +6 |
| Counterparty creator | +6 |
| ExecutionCost creator | 0 |

The fixed annotation differences are accepted for Action/Counterparty; their
production emitters now use Encoder. Annotation logging itself is identical and is
outside this creation-only comparison.

The earlier isolated relay proposal saved 125 gas but omitted generic lane
handling. The implemented takeBalances preserves that handling and returns a
clean cursor. Its shared-helper measurement above supersedes the prototype.
The benchmark requires non-increasing gas for each implemented encoder/count path.

The older execution-optimization fixture converts takeBalances back to calldata
to compare the legacy return value. Its empty-stream case is 23 gas higher;
non-empty cases remain cheaper. That compatibility conversion is reported but
is not used by Relay. The cursor-to-encoder benchmark above retains a strict
no-regression check for empty and non-empty production flows.

## Behavior and mixed-pattern audit

- The cursor execute candidates reject truncated streams with OutOfBounds rather
  than the old upfront InvalidBlock. A malformed suffix is checked after earlier
  hooks, so hook-error precedence can also change; this is not an exact behavior
  replacement even though a reverting transaction rolls back its effects.
- The relay cursor implementation preserves source provenance checks, validates the
  balance stream with expectRunFixed, consumes the state cursor, and calls
  createContext. Tested wrong headers and partial tails retain error order.
  Additional tests cover undeclared lanes, source provenance, metadata, clean
  selections, empty streams, and preservation of the input cursor.
- Relay previously converted stepsCur to calldata, while takeRawBalances converted
  a packed state to calldata and back to abs/end for scanning. takeBalances now
  returns a cursor directly and Relay passes payload cursors to createContext.
  Relay also passes inputCur directly to its migrated hook; see HookCursors.md.
- Credit/Cashout/Settle use Memory.bounds and manual absolute advancement.
  Bootstrap/Debit/Authorize use Cursors.bounds and manual advancement. Replace
  the complete loop pattern, not just the unpacker name.
- Bootstrap still needs block sizes to calculate output capacity. That sizing
  calculation is not duplicate decoder validation.
- Executions.outputCapacity now calls source.runCount(key) directly instead of
  unpacking abs/end for the old runCount call.
- Relay's input, Recover's witness, Pipe's steps, Execute's input, Forward's
  message, and Dispatch's payload now pass through hooks as calldata cursors.
  An internal hook boundary alone is not a reason to convert. Genuinely
  memory-backed state/context/output remain bytes; see HookCursors.md.
  Direct ABI calls, hashing, or event emission may still need materialization.
- InvalidBlock, MalformedBlocks, and EmptyRun are now global declarations in
  utils/Errors.sol with unchanged signatures/selectors. Production references
  to Blocks are now only barrel exports; Decoders and Writers have been removed.

## Recommendation

Counting, the relay cursor flow, and the cheaper composite annotation creators
are implemented using the existing sequential allocation/header/write/wrap
primitives. Annotation payload creators use the Wrap naming convention with
bytes memory inputs. ExecutionCost also migrated at equal measured gas.
Hold execute-loop migrations until
the cursor primitives meet the gas target and the changed failure ordering is
an explicit decision. Do not retain upfront stride validation plus new per-block
checks by accident. Decoders and Writers were subsequently removed.

## Reproduce

```sh
npm run bench -- test/blocks-migration.bench.test.ts
npm test -- test/blocks-migration.test.ts
```

Fixtures: `contracts/test/TestBlocksMigration.sol`. Results are written to
.npm-cache/blocks-migration-execute.json and .npm-cache/blocks-migration-encoding.json.
The execute copies should be refreshed when the production bodies change.
