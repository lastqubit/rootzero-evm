# Settlement gas baseline

Measured with Solidity 0.8.35, optimizer enabled with 200 runs, Cancun EVM target,
and Hardhat's local simulated network. The benchmark host chooses these rates:
20 bps for the executing host as counterparty and 2 bps for other accounts.
`Settlement` itself provides no default `settle` implementation or fee policy.
Results were refreshed on 2026-09-11 with transfers routed through `BookHook.book`
and separate fee credits through `creditAccount`.

Run:

```sh
npm run bench -- test/settlement.bench.test.ts
```

The test writes individual samples to `.npm-cache/settlement-benchmark.json`.
Each row below is the median of three deployments and transactions.

## Results

| Recipient balances | Counterparty | Fee side | Transaction gas | Execution gas |
| --- | --- | --- | ---: | ---: |
| Empty | Host | Debt | 81,392 | 58,812 |
| Empty | Host | Asset | 81,550 | 58,970 |
| Empty | External | Debt | 103,532 | 81,204 |
| Empty | External | Asset | 103,690 | 81,362 |
| Existing | Host | Debt | 47,192 | 24,612 |
| Existing | Host | Asset | 47,350 | 24,770 |
| Existing | External | Debt | 52,232 | 29,904 |
| Existing | External | Asset | 52,390 | 30,062 |

Execution gas subtracts the 21,000 transaction base cost and calldata byte costs
from receipt gas. It still includes the benchmark entrypoint's dispatch and ABI
decoding; it is not an isolated measurement of the internal helper bodies.

## Method

`TestSettlementGas` implements the debit and credit hooks directly with the
`Balances` ledger, without the operation-log instrumentation used by
`TestSettlement`. Deployment and seeding are excluded from the measurements.

Each position has 100,000 asset units and 40,000 liability units, with different
assets on the two sides. Limits select exactly one fee path: the debt maximum
includes the surcharge for debt-fee cases, or equals the debt for asset fallback.
Each run verifies account, counterparty, and fee-recipient balances.

Debited balances start at 100,000 liability units and 200,000 asset units and
remain nonzero. Consequently, these measurements do not include storage-clearing
refunds. In the existing-recipient cases, credit destinations start with nonzero
balances; the empty-recipient cases exercise zero-to-nonzero writes. Every
measurement is a separate transaction, so nonzero balances do not imply warm
storage slots. Host addresses can change calldata costs slightly between samples;
the execution column removes that difference.

## Interpretation

Asset fallback costs 158 additional execution gas relative to debt fees in each
matched scenario. That is small compared with ledger writes. External settlement
costs 5,292 more execution gas with existing recipients, or 22,392 more with empty
recipients, than the corresponding host-counterparty case. External settlement
requires a separate host fee credit, while the host-counterparty case combines
the fee with its credit or retains it through a net debit.

These results support keeping the current simple helper structure. They do not
establish that it is globally optimal or quantify savings against a previous
implementation. Further optimization should compare candidate bytecode against
this baseline, using the same ledger state and fee paths. Production hooks,
events, command/pipeline wrappers, refunds, and storage access patterns can change
the totals materially.
