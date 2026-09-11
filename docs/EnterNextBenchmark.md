# enterNext benchmark

Historical measurements: `Executions.enterNext` has been removed. Production
callers now use `while (exec.more()) { exec.enter(spec); ... }`. The benchmark
fixtures retain frozen combined-entry implementations for comparison; the
`TestEnterNextCurrent` fixture measures today's separate `more`/`enter` loop.
The tables below describe the earlier implementation, not current gas costs.

## Separate entry after removal

Rerunning `npm run bench -- test/enter-next.bench.test.ts
test/shared-enter-next.bench.test.ts` after removal gives:

| Parents | Current more/enter | Frozen shared combined entry |
| ---: | ---: | ---: |
| 0 | 219 | 276 |
| 1 | 2,263 | 2,273 |
| 8 | 16,571 | 16,252 |
| 32 | 65,627 | 64,180 |
| 128 | 261,851 | 255,892 |

The current separate loop retains the improved `Blocks.enter` validation. The
older baseline below predates that improvement, so its gas numbers overstate
the cost of returning to separate calls. Differential checks passed for errors,
both-source exhaustion, child decoding, and packed metadata preservation.
These are isolated fixture measurements, not full `BookPort` transaction costs.

## Historical adoption

Executions now exposes enterNext, and ExchangePort uses it for parent iteration.
The production helper delegates parent validation to Blocks.enter. This keeps
validation centralized at the cost measured below. The differential fixture
exercises production directly and retains the previous inline implementation.

The baseline uses `while (Executions.more(exec))` followed by
the frozen pre-shared-validation `enter(exec, spec)` inside the loop. The current implementation uses
`while (Executions.enterNext(exec, spec))`. Both decode two
ACCOUNT_AMOUNT children per 208-byte parent and retain identical checksums and
packed cursor results. Separate contracts with identical external interfaces
avoid a timed old/new selection branch. Parent specs originate from an immutable.

Solidity 0.8.35, optimizer runs 200, Cancun, without viaIR:

| Parents | Original loop gas | Current enterNext gas | Saved |
| ---: | ---: | ---: | ---: |
| 0 | 219 | 276 | -57 |
| 1 | 2,341 | 2,272 | 69 |
| 8 | 17,195 | 16,244 | 951 |
| 32 | 68,123 | 64,148 | 3,975 |
| 128 | 271,835 | 255,764 | 16,071 |

Measured savings follow `126 * parents - 57`. These are traversal and decoding
execution costs, excluding transaction intrinsic gas, access checks, and account
hooks. Actual ExchangePort transaction savings require an integration benchmark
in the full port; compiler inlining and surrounding code can change the result.

The helper checks both lanes, then calls Blocks.enter and advances input using
one packed decoder load. It preserves the
current validation order, input frame, and all upper metadata bits. It does not
strengthen enter's header-position check into a parent-end check.

Differential tests cover empty/truncated input, wrong keys and lengths, zero-key
specs, exhausted/inverted input bounds, unread/exhausted/inverted state bounds,
and reserved high bits. An explicit regression confirms that exhausted input
with unread state reverts instead of terminating the loop. Loop tests also check
incomplete parents, invalid children, and trailing bytes.

Run `npx hardhat test test/enter-next.bench.test.ts`.
Raw measurements: `.npm-cache/enter-next-results.json`.

## Comparison with the previous inline implementation

Production replaces the inline header read and key/length checks with
`(uint body,) = Blocks.enter(current, spec)`. It still caches the packed decoder,
checks both sources, and updates the input cursor directly.

| Parents | Original more/enter | Previous inline enterNext | Current shared enterNext |
| ---: | ---: | ---: | ---: |
| 0 | 219 | 276 | 276 |
| 1 | 2,341 | 2,196 | 2,272 |
| 8 | 17,195 | 15,636 | 16,244 |
| 32 | 68,123 | 61,716 | 64,148 |
| 128 | 271,835 | 246,036 | 255,764 |

After adopting improved shared validation, the shorter version saves
`126 * parents - 57` against the original loop and costs 76 gas per parent more
than the previous inline implementation. Before that shared change it saved only
`48 * parents - 57`. The shared implementation is adopted to avoid duplicating
validation in this less frequently used helper. In the bytecode comparison,
TestExchange grows by 30 bytes. The previous inline implementation remains
available in TestEnterNext.sol for comparison.
The earlier isolated short-version fixture measured 77 gas extra; production
integration changes compiler output slightly. The current fixture is 1,397
runtime bytes versus 1,367 for the frozen inline version; TestExchange is 2,236
bytes versus its previous 2,206.

The same differential boundary matrix now exercises all three implementations,
including unbounded maximum specs, unread state after input exhaustion, exact
revert bytes, malformed children, and preservation of packed metadata.
