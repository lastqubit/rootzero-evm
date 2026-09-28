# CONTEXT opening comparison

`test/context-opening.bench.test.ts` compares the existing specialized
`Executions.openContext` decoder with `Blocks.unpackContext(Cursors.wrap(context))`
followed by `Cursors.expectEnd(nextCur)`. Both use the same output-capacity
calculation and eager Encoder initialization. The candidate remains test-only.

CONTEXT decoding validates block structure, not account format. The active account
is trusted from its internal caller or trusted peer. Any entrypoint accepting it
from untrusted user input must validate it before constructing or using the context.
Untrusted accounts in nested input still require validation by the consuming command;
authorizing that command does not validate its inputs. See the
[account validation convention](../README.md#account-validation-convention).

With solc 0.8.35, viaIR, optimizer 200, Cancun, the shared version costs 88 more gas
in all 30 valid cases: 0/1/2/4/16 blocks, state-only/input-only/paired sources,
and output allocation enabled/disabled. Returned account, budget, cursors,
output capacity, and buffer size match.

Among 99 valid and malformed context vectors, acceptance matches. Error selectors
change in 70 cases: 68 truncation/boundary failures change from InvalidBlock to
OutOfBounds, and two trailing-data cases change from InvalidBlock to
UnconsumedData. This is a sampled malformed-input comparison, not exhaustive proof.
The production specialized opener is retained, preserving its gas and error behavior.

`Cursors.expectEnd` is a pure full-consumption assertion; `Cursors.exhaust`
advances directly to a validated cursor's end. Execution selectors now reuse
`exhaust` instead of a duplicate private primitive. Encoder is unchanged.
