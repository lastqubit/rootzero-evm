# Output buffer allocation benchmark

> Development snapshot: the measurements below describe the implementation at
> the time of that experiment. The current benchmark fixtures have evolved;
> rerun them for release-specific results.


Run: `npm.cmd test -- test/buffer-allocation.bench.test.ts`.

Measured with Solidity 0.8.35, optimizer enabled with 200 runs, Cancun target, no viaIR, on the Hardhat simulated network. Production allocation is unchanged.

The fixture compares the production run-count scan with a zero-capacity hint (lazy growth) and hints of 1, 2, or 4 times input byte length. All strategies use the production decoder, buffer growth, output encoding, and finish helpers. Every result is checked against independently encoded expected output, including its length and hash.

Gas covers opening, consuming input, writing output, buffer initialization/growth/copying, and finishing. It includes benchmark dispatch and loop overhead; it excludes transaction intrinsic/calldata gas, descriptor construction, and the final output hash. Small differences include strategy dispatch overhead. Memory is the increase in the free memory pointer, including abandoned buffers; it is not the EVM memory high-water mark. Repetitions share one call and accumulate allocations.

The 180 measurements cover 0, 1, 8, 64, and 256 input blocks, with eight repeated executions also measured at 64 blocks. Workloads: equal = ASSET_AMOUNT to BALANCE; expanding = ASSET_AMOUNT to POSITION; shrinking = 256-byte BYTES to BALANCE; variable = BYTES payloads cycling through 0, 16, 256, and 2048 bytes to BALANCE; sparse = one BALANCE per eight ASSET_AMOUNT blocks; unused = consume ASSET_AMOUNT without emitting output despite a nonempty output descriptor. These are input-only, stride-one synthetic commands, not a complete pipeline benchmark.

## Findings

- At 64 equal-size blocks, a 1x byte hint saves 9,893 gas (7.2%) with identical memory use. Lazy growth saves 2,618 gas in one execution but retains about 3.5 times the memory; across eight executions it costs more than scanning.
- Expansion needs an appropriate hint: 4x beats scanning in the 64-block cases, while 1x and 2x grow and copy buffers and lose to scanning across eight executions.
- Large variable-size input makes byte-length hints wasteful. Across eight executions, 4x costs 3,962,996 gas versus 1,051,350 for scanning, and advances the free memory pointer by 1,206,016 bytes versus 38,656.
- With no output, hints allocate no output buffer. Lazy initialization saves the unnecessary scan. Sparse output also benefits from skipping the scan.

Recommendation: keep the scan as the generic policy for now. Exact byte-derived sizing for known fixed-size transformations is worth investigating separately; a universal multiplier or lazy growth is not a consistent improvement.

## 64-block measurements

| Workload | Executions | Strategy | Gas | Memory bytes |
| --- | ---: | --- | ---: | ---: |
| equal | 1 | scan | 137,990 | 4,832 |
| equal | 1 | lazy | 135,372 | 16,864 |
| equal | 1 | bytes1x | 128,097 | 4,832 |
| equal | 1 | bytes2x | 129,089 | 9,440 |
| equal | 1 | bytes4x | 131,315 | 18,656 |
| equal | 8 | scan | 1,106,134 | 38,656 |
| equal | 8 | lazy | 1,113,071 | 134,912 |
| equal | 8 | bytes1x | 1,026,990 | 38,656 |
| equal | 8 | bytes2x | 1,041,948 | 75,520 |
| equal | 8 | bytes4x | 1,087,416 | 149,248 |
| expanding | 1 | scan | 139,395 | 10,976 |
| expanding | 1 | lazy | 140,919 | 33,120 |
| expanding | 1 | bytes1x | 137,875 | 32,608 |
| expanding | 1 | bytes2x | 135,416 | 27,936 |
| expanding | 1 | bytes4x | 131,379 | 18,656 |
| expanding | 8 | scan | 1,127,742 | 87,808 |
| expanding | 8 | lazy | 1,244,233 | 264,960 |
| expanding | 8 | bytes1x | 1,216,283 | 260,864 |
| expanding | 8 | bytes2x | 1,166,400 | 223,488 |
| expanding | 8 | bytes4x | 1,087,928 | 149,248 |
| shrinking | 1 | scan | 130,438 | 4,832 |
| shrinking | 1 | lazy | 127,820 | 16,864 |
| shrinking | 1 | bytes1x | 123,370 | 17,120 |
| shrinking | 1 | bytes2x | 128,194 | 34,016 |
| shrinking | 1 | bytes4x | 141,109 | 67,808 |
| shrinking | 8 | scan | 1,045,718 | 38,656 |
| shrinking | 8 | lazy | 1,052,655 | 134,912 |
| shrinking | 8 | bytes1x | 1,017,982 | 136,960 |
| shrinking | 8 | bytes2x | 1,148,860 | 272,128 |
| shrinking | 8 | bytes4x | 1,619,704 | 542,464 |
| variable | 1 | scan | 131,142 | 4,832 |
| variable | 1 | lazy | 128,524 | 16,864 |
| variable | 1 | bytes1x | 130,146 | 37,856 |
| variable | 1 | bytes2x | 145,356 | 75,488 |
| variable | 1 | bytes4x | 191,983 | 150,752 |
| variable | 8 | scan | 1,051,350 | 38,656 |
| variable | 8 | lazy | 1,058,287 | 134,912 |
| variable | 8 | bytes1x | 1,193,957 | 302,848 |
| variable | 8 | bytes2x | 1,771,226 | 603,904 |
| variable | 8 | bytes4x | 3,962,996 | 1,206,016 |
| sparse | 1 | scan | 89,950 | 4,832 |
| sparse | 1 | lazy | 81,561 | 2,336 |
| sparse | 1 | bytes1x | 80,057 | 4,832 |
| sparse | 1 | bytes2x | 81,049 | 9,440 |
| sparse | 1 | bytes4x | 83,275 | 18,656 |
| sparse | 8 | scan | 721,814 | 38,656 |
| sparse | 8 | lazy | 652,788 | 18,688 |
| sparse | 8 | bytes1x | 642,670 | 38,656 |
| sparse | 8 | bytes2x | 657,628 | 75,520 |
| sparse | 8 | bytes4x | 703,096 | 149,248 |
| unused | 1 | scan | 75,111 | 192 |
| unused | 1 | lazy | 65,035 | 192 |
| unused | 1 | bytes1x | 65,218 | 192 |
| unused | 1 | bytes2x | 65,218 | 192 |
| unused | 1 | bytes4x | 65,218 | 192 |
| unused | 8 | scan | 600,606 | 1,536 |
| unused | 8 | lazy | 519,998 | 1,536 |
| unused | 8 | bytes1x | 521,462 | 1,536 |
| unused | 8 | bytes2x | 521,462 | 1,536 |
| unused | 8 | bytes4x | 521,462 | 1,536 |

## All measurements

| Workload | Blocks | Executions | Strategy | Input bytes | Output bytes | Gas | Memory bytes |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |
| equal | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| equal | 0 | 1 | lazy | 0 | 0 | 971 | 192 |
| equal | 0 | 1 | bytes1x | 0 | 0 | 1,154 | 192 |
| equal | 0 | 1 | bytes2x | 0 | 0 | 1,154 | 192 |
| equal | 0 | 1 | bytes4x | 0 | 0 | 1,154 | 192 |
| equal | 1 | 1 | scan | 72 | 72 | 4,357 | 320 |
| equal | 1 | 1 | lazy | 72 | 72 | 3,689 | 352 |
| equal | 1 | 1 | bytes1x | 72 | 72 | 3,599 | 320 |
| equal | 1 | 1 | bytes2x | 72 | 72 | 3,611 | 384 |
| equal | 1 | 1 | bytes4x | 72 | 72 | 3,635 | 512 |
| equal | 8 | 1 | scan | 576 | 576 | 19,197 | 800 |
| equal | 8 | 1 | lazy | 576 | 576 | 19,729 | 2,336 |
| equal | 8 | 1 | bytes1x | 576 | 576 | 17,424 | 800 |
| equal | 8 | 1 | bytes2x | 576 | 576 | 17,535 | 1,376 |
| equal | 8 | 1 | bytes4x | 576 | 576 | 17,760 | 2,528 |
| equal | 64 | 1 | scan | 4,608 | 4,608 | 137,990 | 4,832 |
| equal | 64 | 1 | lazy | 4,608 | 4,608 | 135,372 | 16,864 |
| equal | 64 | 1 | bytes1x | 4,608 | 4,608 | 128,097 | 4,832 |
| equal | 64 | 1 | bytes2x | 4,608 | 4,608 | 129,089 | 9,440 |
| equal | 64 | 1 | bytes4x | 4,608 | 4,608 | 131,315 | 18,656 |
| equal | 64 | 8 | scan | 4,608 | 4,608 | 1,106,134 | 38,656 |
| equal | 64 | 8 | lazy | 4,608 | 4,608 | 1,113,071 | 134,912 |
| equal | 64 | 8 | bytes1x | 4,608 | 4,608 | 1,026,990 | 38,656 |
| equal | 64 | 8 | bytes2x | 4,608 | 4,608 | 1,041,948 | 75,520 |
| equal | 64 | 8 | bytes4x | 4,608 | 4,608 | 1,087,416 | 149,248 |
| equal | 256 | 1 | scan | 18,432 | 18,432 | 545,752 | 18,656 |
| equal | 256 | 1 | lazy | 18,432 | 18,432 | 532,671 | 66,144 |
| equal | 256 | 1 | bytes1x | 18,432 | 18,432 | 508,019 | 18,656 |
| equal | 256 | 1 | bytes2x | 18,432 | 18,432 | 513,444 | 37,088 |
| equal | 256 | 1 | bytes4x | 18,432 | 18,432 | 528,182 | 73,952 |
| expanding | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| expanding | 0 | 1 | lazy | 0 | 0 | 971 | 192 |
| expanding | 0 | 1 | bytes1x | 0 | 0 | 1,154 | 192 |
| expanding | 0 | 1 | bytes2x | 0 | 0 | 1,154 | 192 |
| expanding | 0 | 1 | bytes4x | 0 | 0 | 1,154 | 192 |
| expanding | 1 | 1 | scan | 72 | 168 | 4,376 | 416 |
| expanding | 1 | 1 | lazy | 72 | 168 | 3,847 | 480 |
| expanding | 1 | 1 | bytes1x | 72 | 168 | 4,001 | 512 |
| expanding | 1 | 1 | bytes2x | 72 | 168 | 3,868 | 512 |
| expanding | 1 | 1 | bytes4x | 72 | 168 | 3,636 | 512 |
| expanding | 8 | 1 | scan | 576 | 1,344 | 19,353 | 1,568 |
| expanding | 8 | 1 | lazy | 576 | 1,344 | 20,339 | 4,256 |
| expanding | 8 | 1 | bytes1x | 576 | 1,344 | 19,515 | 4,384 |
| expanding | 8 | 1 | bytes2x | 576 | 1,344 | 18,722 | 3,744 |
| expanding | 8 | 1 | bytes4x | 576 | 1,344 | 17,768 | 2,528 |
| expanding | 64 | 1 | scan | 4,608 | 10,752 | 139,395 | 10,976 |
| expanding | 64 | 1 | lazy | 4,608 | 10,752 | 140,919 | 33,120 |
| expanding | 64 | 1 | bytes1x | 4,608 | 10,752 | 137,875 | 32,608 |
| expanding | 64 | 1 | bytes2x | 4,608 | 10,752 | 135,416 | 27,936 |
| expanding | 64 | 1 | bytes4x | 4,608 | 10,752 | 131,379 | 18,656 |
| expanding | 64 | 8 | scan | 4,608 | 10,752 | 1,127,742 | 87,808 |
| expanding | 64 | 8 | lazy | 4,608 | 10,752 | 1,244,233 | 264,960 |
| expanding | 64 | 8 | bytes1x | 4,608 | 10,752 | 1,216,283 | 260,864 |
| expanding | 64 | 8 | bytes2x | 4,608 | 10,752 | 1,166,400 | 223,488 |
| expanding | 64 | 8 | bytes4x | 4,608 | 10,752 | 1,087,928 | 149,248 |
| expanding | 256 | 1 | scan | 18,432 | 43,008 | 553,529 | 43,232 |
| expanding | 256 | 1 | lazy | 18,432 | 43,008 | 573,067 | 131,552 |
| expanding | 256 | 1 | bytes1x | 18,432 | 43,008 | 566,750 | 129,376 |
| expanding | 256 | 1 | bytes2x | 18,432 | 43,008 | 552,463 | 110,880 |
| expanding | 256 | 1 | bytes4x | 18,432 | 43,008 | 528,438 | 73,952 |
| shrinking | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| shrinking | 0 | 1 | lazy | 0 | 0 | 971 | 192 |
| shrinking | 0 | 1 | bytes1x | 0 | 0 | 1,154 | 192 |
| shrinking | 0 | 1 | bytes2x | 0 | 0 | 1,154 | 192 |
| shrinking | 0 | 1 | bytes4x | 0 | 0 | 1,154 | 192 |
| shrinking | 1 | 1 | scan | 264 | 72 | 4,239 | 320 |
| shrinking | 1 | 1 | lazy | 264 | 72 | 3,571 | 352 |
| shrinking | 1 | 1 | bytes1x | 264 | 72 | 3,517 | 512 |
| shrinking | 1 | 1 | bytes2x | 264 | 72 | 3,566 | 768 |
| shrinking | 1 | 1 | bytes4x | 264 | 72 | 3,664 | 1,280 |
| shrinking | 8 | 1 | scan | 2,112 | 576 | 18,253 | 800 |
| shrinking | 8 | 1 | lazy | 2,112 | 576 | 18,785 | 2,336 |
| shrinking | 8 | 1 | bytes1x | 2,112 | 576 | 16,778 | 2,336 |
| shrinking | 8 | 1 | bytes2x | 2,112 | 576 | 17,202 | 4,448 |
| shrinking | 8 | 1 | bytes4x | 2,112 | 576 | 18,102 | 8,672 |
| shrinking | 64 | 1 | scan | 16,896 | 4,608 | 130,438 | 4,832 |
| shrinking | 64 | 1 | lazy | 16,896 | 4,608 | 127,820 | 16,864 |
| shrinking | 64 | 1 | bytes1x | 16,896 | 4,608 | 123,370 | 17,120 |
| shrinking | 64 | 1 | bytes2x | 16,896 | 4,608 | 128,194 | 34,016 |
| shrinking | 64 | 1 | bytes4x | 16,896 | 4,608 | 141,109 | 67,808 |
| shrinking | 64 | 8 | scan | 16,896 | 4,608 | 1,045,718 | 38,656 |
| shrinking | 64 | 8 | lazy | 16,896 | 4,608 | 1,052,655 | 134,912 |
| shrinking | 64 | 8 | bytes1x | 16,896 | 4,608 | 1,017,982 | 136,960 |
| shrinking | 64 | 8 | bytes2x | 16,896 | 4,608 | 1,148,860 | 272,128 |
| shrinking | 64 | 8 | bytes4x | 16,896 | 4,608 | 1,619,704 | 542,464 |
| shrinking | 256 | 1 | scan | 67,584 | 18,432 | 515,544 | 18,656 |
| shrinking | 256 | 1 | lazy | 67,584 | 18,432 | 502,463 | 66,144 |
| shrinking | 256 | 1 | bytes1x | 67,584 | 18,432 | 495,157 | 67,808 |
| shrinking | 256 | 1 | bytes2x | 67,584 | 18,432 | 534,056 | 135,392 |
| shrinking | 256 | 1 | bytes4x | 67,584 | 18,432 | 664,126 | 270,560 |
| variable | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| variable | 0 | 1 | lazy | 0 | 0 | 971 | 192 |
| variable | 0 | 1 | bytes1x | 0 | 0 | 1,154 | 192 |
| variable | 0 | 1 | bytes2x | 0 | 0 | 1,154 | 192 |
| variable | 0 | 1 | bytes4x | 0 | 0 | 1,154 | 192 |
| variable | 1 | 1 | scan | 8 | 72 | 4,250 | 320 |
| variable | 1 | 1 | lazy | 8 | 72 | 3,582 | 352 |
| variable | 1 | 1 | bytes1x | 8 | 72 | 4,129 | 352 |
| variable | 1 | 1 | bytes2x | 8 | 72 | 3,996 | 352 |
| variable | 1 | 1 | bytes4x | 8 | 72 | 3,863 | 352 |
| variable | 8 | 1 | scan | 4,704 | 576 | 18,341 | 800 |
| variable | 8 | 1 | lazy | 4,704 | 576 | 18,873 | 2,336 |
| variable | 8 | 1 | bytes1x | 4,704 | 576 | 17,389 | 4,928 |
| variable | 8 | 1 | bytes2x | 4,704 | 576 | 18,404 | 9,632 |
| variable | 8 | 1 | bytes4x | 4,704 | 576 | 20,687 | 19,040 |
| variable | 64 | 1 | scan | 37,632 | 4,608 | 131,142 | 4,832 |
| variable | 64 | 1 | lazy | 37,632 | 4,608 | 128,524 | 16,864 |
| variable | 64 | 1 | bytes1x | 37,632 | 4,608 | 130,146 | 37,856 |
| variable | 64 | 1 | bytes2x | 37,632 | 4,608 | 145,356 | 75,488 |
| variable | 64 | 1 | bytes4x | 37,632 | 4,608 | 191,983 | 150,752 |
| variable | 64 | 8 | scan | 37,632 | 4,608 | 1,051,350 | 38,656 |
| variable | 64 | 8 | lazy | 37,632 | 4,608 | 1,058,287 | 134,912 |
| variable | 64 | 8 | bytes1x | 37,632 | 4,608 | 1,193,957 | 302,848 |
| variable | 64 | 8 | bytes2x | 37,632 | 4,608 | 1,771,226 | 603,904 |
| variable | 64 | 8 | bytes4x | 37,632 | 4,608 | 3,962,996 | 1,206,016 |
| variable | 256 | 1 | scan | 150,528 | 18,432 | 518,360 | 18,656 |
| variable | 256 | 1 | lazy | 150,528 | 18,432 | 505,279 | 66,144 |
| variable | 256 | 1 | bytes1x | 150,528 | 18,432 | 548,143 | 150,752 |
| variable | 256 | 1 | bytes2x | 150,528 | 18,432 | 706,223 | 301,280 |
| variable | 256 | 1 | bytes4x | 150,528 | 18,432 | 1,281,691 | 602,336 |
| sparse | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| sparse | 0 | 1 | lazy | 0 | 0 | 971 | 192 |
| sparse | 0 | 1 | bytes1x | 0 | 0 | 1,154 | 192 |
| sparse | 0 | 1 | bytes2x | 0 | 0 | 1,154 | 192 |
| sparse | 0 | 1 | bytes4x | 0 | 0 | 1,154 | 192 |
| sparse | 1 | 1 | scan | 72 | 72 | 4,421 | 320 |
| sparse | 1 | 1 | lazy | 72 | 72 | 3,753 | 352 |
| sparse | 1 | 1 | bytes1x | 72 | 72 | 3,663 | 320 |
| sparse | 1 | 1 | bytes2x | 72 | 72 | 3,675 | 384 |
| sparse | 1 | 1 | bytes4x | 72 | 72 | 3,699 | 512 |
| sparse | 8 | 1 | scan | 576 | 72 | 13,192 | 800 |
| sparse | 8 | 1 | lazy | 576 | 72 | 11,418 | 352 |
| sparse | 8 | 1 | bytes1x | 576 | 72 | 11,419 | 800 |
| sparse | 8 | 1 | bytes2x | 576 | 72 | 11,530 | 1,376 |
| sparse | 8 | 1 | bytes4x | 576 | 72 | 11,755 | 2,528 |
| sparse | 64 | 1 | scan | 4,608 | 576 | 89,950 | 4,832 |
| sparse | 64 | 1 | lazy | 4,608 | 576 | 81,561 | 2,336 |
| sparse | 64 | 1 | bytes1x | 4,608 | 576 | 80,057 | 4,832 |
| sparse | 64 | 1 | bytes2x | 4,608 | 576 | 81,049 | 9,440 |
| sparse | 64 | 1 | bytes4x | 4,608 | 576 | 83,275 | 18,656 |
| sparse | 64 | 8 | scan | 4,608 | 576 | 721,814 | 38,656 |
| sparse | 64 | 8 | lazy | 4,608 | 576 | 652,788 | 18,688 |
| sparse | 64 | 8 | bytes1x | 4,608 | 576 | 642,670 | 38,656 |
| sparse | 64 | 8 | bytes2x | 4,608 | 576 | 657,628 | 75,520 |
| sparse | 64 | 8 | bytes4x | 4,608 | 576 | 703,096 | 149,248 |
| sparse | 256 | 1 | scan | 18,432 | 2,304 | 353,592 | 18,656 |
| sparse | 256 | 1 | lazy | 18,432 | 2,304 | 316,970 | 8,608 |
| sparse | 256 | 1 | bytes1x | 18,432 | 2,304 | 315,859 | 18,656 |
| sparse | 256 | 1 | bytes2x | 18,432 | 2,304 | 321,284 | 37,088 |
| sparse | 256 | 1 | bytes4x | 18,432 | 2,304 | 336,022 | 73,952 |
| unused | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| unused | 0 | 1 | lazy | 0 | 0 | 971 | 192 |
| unused | 0 | 1 | bytes1x | 0 | 0 | 1,154 | 192 |
| unused | 0 | 1 | bytes2x | 0 | 0 | 1,154 | 192 |
| unused | 0 | 1 | bytes4x | 0 | 0 | 1,154 | 192 |
| unused | 1 | 1 | scan | 72 | 0 | 2,913 | 192 |
| unused | 1 | 1 | lazy | 72 | 0 | 1,972 | 192 |
| unused | 1 | 1 | bytes1x | 72 | 0 | 2,155 | 192 |
| unused | 1 | 1 | bytes2x | 72 | 0 | 2,155 | 192 |
| unused | 1 | 1 | bytes4x | 72 | 0 | 2,155 | 192 |
| unused | 8 | 1 | scan | 576 | 0 | 10,935 | 192 |
| unused | 8 | 1 | lazy | 576 | 0 | 8,979 | 192 |
| unused | 8 | 1 | bytes1x | 576 | 0 | 9,162 | 192 |
| unused | 8 | 1 | bytes2x | 576 | 0 | 9,162 | 192 |
| unused | 8 | 1 | bytes4x | 576 | 0 | 9,162 | 192 |
| unused | 64 | 1 | scan | 4,608 | 0 | 75,111 | 192 |
| unused | 64 | 1 | lazy | 4,608 | 0 | 65,035 | 192 |
| unused | 64 | 1 | bytes1x | 4,608 | 0 | 65,218 | 192 |
| unused | 64 | 1 | bytes2x | 4,608 | 0 | 65,218 | 192 |
| unused | 64 | 1 | bytes4x | 4,608 | 0 | 65,218 | 192 |
| unused | 64 | 8 | scan | 4,608 | 0 | 600,606 | 1,536 |
| unused | 64 | 8 | lazy | 4,608 | 0 | 519,998 | 1,536 |
| unused | 64 | 8 | bytes1x | 4,608 | 0 | 521,462 | 1,536 |
| unused | 64 | 8 | bytes2x | 4,608 | 0 | 521,462 | 1,536 |
| unused | 64 | 8 | bytes4x | 4,608 | 0 | 521,462 | 1,536 |
| unused | 256 | 1 | scan | 18,432 | 0 | 295,143 | 192 |
| unused | 256 | 1 | lazy | 18,432 | 0 | 257,227 | 192 |
| unused | 256 | 1 | bytes1x | 18,432 | 0 | 257,410 | 192 |
| unused | 256 | 1 | bytes2x | 18,432 | 0 | 257,410 | 192 |
| unused | 256 | 1 | bytes4x | 18,432 | 0 | 257,410 | 192 |
