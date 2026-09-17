# Settlement gas baseline

Measured on 2026-09-17 with Solidity 0.8.35, optimizer enabled with 200 runs,
Cancun EVM target, and Hardhat's local simulated network. The benchmark caller checks
packed limits before settlement applies final position quantities without host fees.
Account validation is delegated to the account hooks. This benchmark's ledger
accepts opaque account IDs and performs no account-format check.

Run:

```sh
npm run bench -- test/settlement.bench.test.ts
```

The test writes samples to `.npm-cache/settlement-benchmark.json`. Each row is
the median of three deployments and transactions.

## Results

| Recipient balances | Counterparty | Transaction gas | Execution gas |
| --- | --- | ---: | ---: |
| Empty | Rootzero | 50,853 | 28,701 |
| Empty | Host | 79,148 | 56,696 |
| Empty | External | 78,896 | 56,696 |
| Existing | Rootzero | 33,753 | 11,601 |
| Existing | Host | 44,948 | 22,496 |
| Existing | External | 44,696 | 22,496 |

Execution gas subtracts the 21,000 transaction base cost and calldata byte costs
from receipt gas. It includes entrypoint dispatch and ABI decoding. Host and
external counterparties execute the same path; their transaction gas differs
because of the number of nonzero bytes in their encoded account identifiers.

## Method

`TestSettlementGas` implements account hooks with the `Balances` ledger, without
operation-log instrumentation. Deployment and seeding are excluded. Each position
has 100,000 asset units and 40,000 liability units, with exact packed limits and
different assets on the two sides. All final balances are verified, including the
absence of separate host credits.

Rootzero positions debit the active account's liability and credit its asset.
Account counterparties require two transfers: liability to the counterparty,
then assets to the active account. Each transfer debits before crediting.

Debited balances remain nonzero, so there are no storage-clearing refunds.
Existing recipients start with one unit; empty recipients start with zero.
Each measurement is a separate transaction, so existing balances do not imply
warm storage slots. Production hooks, events, command wrappers, and different
storage access patterns may change the totals.

## Comparison with host fees

The previous packed-limits baseline with a debt-side host fee used 58,843
execution gas for an empty host counterparty and 81,235 for an empty external
counterparty. Exact settlement uses 56,696 for either: reductions of 2,147 and
24,539 gas respectively. With existing recipients, the reductions are 2,147
and 7,439 gas. The external reduction includes eliminating a separate host fee
credit. These flows have different fee effects; this comparison does not include
the cost of any fees handled upstream by position producers.
Compared with the 1.39.0 baseline, Rootzero booking uses 5 fewer execution gas
and account exchanges use 10 more. Hosts that validate accounts in their hooks
will incur the cost of their chosen checks.
