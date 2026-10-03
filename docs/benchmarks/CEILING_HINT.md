# Ceiling-division allocation benchmark

> Development snapshot: the measurements below describe the implementation at
> the time of that experiment. The current benchmark fixtures have evolved;
> rerun them for release-specific results.


Run: `npm.cmd test -- test/buffer-allocation.bench.test.ts`.

Production code is unchanged. All 468 measurements passed independent expected-output length and hash checks. Solidity 0.8.35, optimizer 200 runs, Cancun, no viaIR; Hardhat simulated network.

The new ceiling strategy estimates groups as length / sourceGroupSize, adding one for a nonzero remainder. A zero group size starts with zero capacity and uses normal buffer growth. It never calls runCount. Source group size and output group size are calculated from benchmark descriptor metadata inside the measured interval, so this isolates the allocation algorithm without implementing the proposed descriptor layout or precomputing group sizes.

Source hints include the header: ASSET_AMOUNT = 72 bytes, BYTES = 136 bytes. Output encoded sizes are 72 bytes for BALANCE and 168 for POSITION. Source metadata is packed before measurement into reserved descriptor bits. All workloads use input-only, stride-one descriptors. State-driven and grouped execution are not covered.

Gas includes opening, decoding, output writes, allocations, resizing/copying, finishing, and benchmark dispatch/loop overhead. It excludes descriptor construction, final hashing, transaction intrinsic gas and calldata gas. Memory is free-memory-pointer growth, including abandoned buffers. Repetitions share one call and accumulate memory. Compare current-run strategies; small differences from previous reports reflect fixture dispatch changes.

Workloads: equal ASSET_AMOUNT to BALANCE; expanding ASSET_AMOUNT to POSITION; shrinking 256-byte BYTES payloads to BALANCE; variable BYTES payloads cycling through 0/16/256/2048 bytes; sparse one output every eight ASSET_AMOUNT blocks; unused consumes without output; underestimate empty BYTES payloads; overestimate 264-byte BYTES payloads; zero_hint 128-byte BYTES payloads with source hint explicitly zero.

Counts: 0, 1, 8, 17, 64, 256. At 64 blocks, all seven strategies also run eight repetitions; scan/divisible/ceiling additionally run 32 repetitions. Output equality is checked on the final result of each call.

## Findings

- At 64 equal-size blocks, ceiling saves 9,420 gas (6.7%) versus scanning with identical memory. Expansion saves the same amount. It beats the divisibility shortcut by only 51 gas for these fixed-size streams.
- At 64 shrinking blocks, ceiling saves 8,403 gas but retains 9,248 bytes versus 4,832. At 64 variable blocks it saves 5,731 gas but retains 20,192 bytes versus 4,832.
- Across 32 executions of 64 variable blocks, ceiling costs 4,818,150 gas versus 4,274,294 for scanning: 12.7% more. Retained memory is 646,144 versus 154,624 bytes. The divisibility strategy falls back to scanning for this workload.
- Zero hints correctly use lazy growth, but accumulated allocations make 32 executions cost 4,720,210 gas versus 4,302,966 for scanning.
- Deliberately inaccurate estimates still produce correct output. The memory/gas tradeoff depends on the stream and repetition count; no scan is not a universal improvement. The divisibility fallback remains the more conservative generic policy among the two proposed shortcuts.

## Comparison at 64 blocks

| Workload | Executions | Strategy | Gas | Memory bytes |
| --- | ---: | --- | ---: | ---: |
| equal | 1 | scan | 139,974 | 4,832 |
| equal | 1 | divisible | 130,605 | 4,832 |
| equal | 1 | ceiling | 130,554 | 4,832 |
| equal | 8 | scan | 1,122,006 | 38,656 |
| equal | 8 | divisible | 1,047,054 | 38,656 |
| equal | 8 | ceiling | 1,046,646 | 38,656 |
| equal | 32 | scan | 4,522,102 | 154,624 |
| equal | 32 | divisible | 4,222,294 | 154,624 |
| equal | 32 | ceiling | 4,220,662 | 154,624 |
| expanding | 1 | scan | 141,379 | 10,976 |
| expanding | 1 | divisible | 132,010 | 10,976 |
| expanding | 1 | ceiling | 131,959 | 10,976 |
| expanding | 8 | scan | 1,143,614 | 87,808 |
| expanding | 8 | divisible | 1,068,662 | 87,808 |
| expanding | 8 | ceiling | 1,068,254 | 87,808 |
| expanding | 32 | scan | 4,750,806 | 351,232 |
| expanding | 32 | divisible | 4,450,998 | 351,232 |
| expanding | 32 | ceiling | 4,449,366 | 351,232 |
| shrinking | 1 | scan | 131,526 | 4,832 |
| shrinking | 1 | divisible | 131,629 | 4,832 |
| shrinking | 1 | ceiling | 123,123 | 9,248 |
| shrinking | 8 | scan | 1,054,422 | 38,656 |
| shrinking | 8 | divisible | 1,055,246 | 38,656 |
| shrinking | 8 | ceiling | 993,837 | 73,984 |
| shrinking | 32 | scan | 4,251,766 | 154,624 |
| shrinking | 32 | divisible | 4,255,062 | 154,624 |
| shrinking | 32 | ceiling | 4,100,507 | 295,936 |
| variable | 1 | scan | 132,230 | 4,832 |
| variable | 1 | divisible | 132,333 | 4,832 |
| variable | 1 | ceiling | 126,499 | 20,192 |
| variable | 8 | scan | 1,060,054 | 38,656 |
| variable | 8 | divisible | 1,060,878 | 38,656 |
| variable | 8 | ceiling | 1,055,258 | 161,536 |
| variable | 32 | scan | 4,274,294 | 154,624 |
| variable | 32 | divisible | 4,277,590 | 154,624 |
| variable | 32 | ceiling | 4,818,150 | 646,144 |
| sparse | 1 | scan | 91,934 | 4,832 |
| sparse | 1 | divisible | 82,565 | 4,832 |
| sparse | 1 | ceiling | 82,514 | 4,832 |
| sparse | 8 | scan | 737,686 | 38,656 |
| sparse | 8 | divisible | 662,734 | 38,656 |
| sparse | 8 | ceiling | 662,326 | 38,656 |
| sparse | 32 | scan | 2,984,822 | 154,624 |
| sparse | 32 | divisible | 2,685,014 | 154,624 |
| sparse | 32 | ceiling | 2,683,382 | 154,624 |
| unused | 1 | scan | 77,107 | 192 |
| unused | 1 | divisible | 67,738 | 192 |
| unused | 1 | ceiling | 67,687 | 192 |
| unused | 8 | scan | 616,574 | 1,536 |
| unused | 8 | divisible | 541,622 | 1,536 |
| unused | 8 | ceiling | 541,214 | 1,536 |
| unused | 32 | scan | 2,466,228 | 6,144 |
| unused | 32 | divisible | 2,166,420 | 6,144 |
| unused | 32 | ceiling | 2,164,788 | 6,144 |
| underestimate | 1 | scan | 133,126 | 4,832 |
| underestimate | 1 | divisible | 133,229 | 4,832 |
| underestimate | 1 | ceiling | 127,624 | 9,408 |
| underestimate | 8 | scan | 1,067,222 | 38,656 |
| underestimate | 8 | divisible | 1,068,046 | 38,656 |
| underestimate | 8 | ceiling | 1,030,162 | 75,264 |
| underestimate | 32 | scan | 4,302,966 | 154,624 |
| underestimate | 32 | divisible | 4,306,262 | 154,624 |
| underestimate | 32 | ceiling | 4,250,180 | 301,056 |
| overestimate | 1 | scan | 133,126 | 4,832 |
| overestimate | 1 | divisible | 124,749 | 9,440 |
| overestimate | 1 | ceiling | 124,698 | 9,440 |
| overestimate | 8 | scan | 1,067,222 | 38,656 |
| overestimate | 8 | divisible | 1,007,228 | 75,520 |
| overestimate | 8 | ceiling | 1,006,820 | 75,520 |
| overestimate | 32 | scan | 4,302,966 | 154,624 |
| overestimate | 32 | divisible | 4,159,326 | 302,080 |
| overestimate | 32 | ceiling | 4,157,694 | 302,080 |
| zero_hint | 1 | scan | 133,126 | 4,832 |
| zero_hint | 1 | divisible | 133,165 | 4,832 |
| zero_hint | 1 | ceiling | 130,730 | 16,864 |
| zero_hint | 8 | scan | 1,067,222 | 38,656 |
| zero_hint | 8 | divisible | 1,067,534 | 38,656 |
| zero_hint | 8 | ceiling | 1,075,935 | 134,912 |
| zero_hint | 32 | scan | 4,302,966 | 154,624 |
| zero_hint | 32 | divisible | 4,304,214 | 154,624 |
| zero_hint | 32 | ceiling | 4,720,210 | 539,648 |

The complete current-run data is written to `.npm-cache/buffer-allocation-results.json` by the benchmark.
