# Burn execution runner benchmark

`Burn` uses `CommandBase.runCommand(context, descriptor, burnOne)` to process its state.
The benchmark retains the previous `openCommand` / `more` / `close` implementation
in `TestBurnLoopHost` and compares it with `TestBurnHost`, which inherits the
updated production command.

Run with:

```sh
npm run bench -- test/burn-run.bench.test.ts
```

## Setup

Solidity 0.8.35, optimizer enabled with 200 runs, Cancun EVM target, and the
repository's Hardhat simulated network. Both hosts use the same `burn(bytes)`
selector, calldata, authorization setup, and hook emitting one `BurnCalled` event
per balance. Each measurement is a separate transaction receipt, so the numbers
include intrinsic transaction gas, calldata, authorization, decoding, events,
and return encoding. They are not isolated callback costs.

The benchmark checks identical return values and event topics/data, and matching
revert data for invalid contexts, malformed state, unexpected input, and an
unauthorized caller. Runtime sizes describe the complete test hosts.

## Results

| Balances | Original loop gas | Runner gas | Runner minus loop |
| ---: | ---: | ---: | ---: |
| 0 | 26,907 | 26,704 | -203 |
| 1 | 29,815 | 29,647 | -168 |
| 2 | 32,839 | 32,706 | -133 |
| 8 | 50,379 | 50,456 | +77 |
| 32 | 120,639 | 121,556 | +917 |
| 128 | 401,727 | 406,004 | +4,277 |

Runtime bytecode grows from 6,186 to 6,303 bytes: **117 additional bytes**.

At the measured batch sizes, the gas difference follows `-203 + 35 * balances`.
The runner saves gas for the measured zero-, one-, and two-item batches; the
measured eight-, 32-, and 128-item batches cost more. This does not establish a
universal callback cost: compiler settings, host composition, and hook
implementations can change the result. These figures use the endpoint-base
runner and shared `openContext` initializer.

Machine-readable results are written to `.npm-cache/burn-run-results.json`.
