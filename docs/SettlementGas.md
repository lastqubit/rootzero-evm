# Settlement gas baseline

Measured on 2026-09-14 with Solidity 0.8.35, optimizer enabled with 200 runs,
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
| Empty | Rootzero | 50,858 | 28,706 |
| Empty | Host | 79,138 | 56,686 |
| Empty | External | 78,886 | 56,686 |
| Existing | Rootzero | 33,758 | 11,606 |
| Existing | Host | 44,938 | 22,486 |
| Existing | External | 44,686 | 22,486 |

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
counterparty. Exact settlement uses 56,686 for either: reductions of 2,157 and
24,549 gas respectively. With existing recipients, the reductions are 2,157
and 7,449 gas. The external reduction includes eliminating a separate host fee
credit. These flows have different fee effects; this comparison does not include
the cost of any fees handled upstream by position producers.
Delegating account validation removes another 90 execution gas per account
exchange from the preceding exact-settlement baseline. Hosts that validate
accounts in their hooks will incur the cost of their chosen checks.
