# Divisible source-hint allocation benchmark

> Development snapshot: the measurements below describe the implementation at
> the time of that experiment. The current benchmark fixtures have evolved;
> rerun them for release-specific results.


Run: `npm.cmd test -- test/buffer-allocation.bench.test.ts`.

Production code is unchanged. This extends the original allocation benchmark with a divisibility strategy. All 336 measurements passed independently encoded output length and hash checks. Solidity 0.8.35, optimizer 200 runs, Cancun, no viaIR; Hardhat simulated network.

The fixture stores an encoded source hint in reserved descriptor bits 8..39 before measurement, standing in for metadata created at deployment. It reads the existing input stride, calculates groupSize = sourceHint * sourceStride, and uses input.length / groupSize when divisible and nonzero. Otherwise it uses runCount / sourceStride. Output capacity is estimated groups * output stride * encoded output hint. This tests the allocation algorithm, not the proposed uniform descriptor layout.

Source hints include the 8-byte header: ASSET_AMOUNT uses 72 bytes; BYTES uses 136 bytes (its current 128-byte payload hint). All cases use input-only, stride-one descriptors. Grouped/state-driven execution and a zero source hint are not covered here.

Gas includes opening, decoding, output writing, buffer allocation/growth/copying, finishing, and benchmark dispatch/loop overhead. Descriptor construction, final output hashing, transaction intrinsic gas and calldata gas are excluded. Memory is free-memory-pointer growth, including abandoned buffers. Eight repetitions share one call. Compare strategies within this run: the expanded workload dispatch changes absolute gas compared with the earlier benchmark.

## Findings

- For 64 equal-size or expanding blocks, the shortcut saves 9,403 gas with identical memory: 6.7% and 6.7%, respectively.
- For the 64-block shrinking and variable workloads, nondivisible lengths trigger scanning; the added cost is 69 gas per execution in this fixture.
- Deliberate underestimation: 17 empty BYTES blocks occupy 136 bytes, so the shortcut estimates one output instead of 17. Output is correct, but gas increases from 36,997 to 38,429 and memory from 1,472 to 5,120 bytes.
- Deliberate overestimation: each BYTES block has a 264-byte payload (272 encoded bytes), twice the source hint. At 64 blocks gas falls from 133,126 to 124,715, but memory rises from 4,832 to 9,440 bytes. This tradeoff is workload-dependent.

The shortcut is promising for fixed-size streams and has modest fallback overhead here. Divisibility is an allocation heuristic, not validation. These synthetic cases do not establish how frequently real variable-size streams misestimate.

## Current-run comparison (64 blocks, plus the 17-block underestimate)

| Workload | Blocks | Executions | Strategy | Gas | Memory bytes |
| --- | ---: | ---: | --- | ---: | ---: |
| equal | 64 | 1 | scan | 139,974 | 4,832 |
| equal | 64 | 1 | divisible | 130,571 | 4,832 |
| equal | 64 | 8 | scan | 1,122,006 | 38,656 |
| equal | 64 | 8 | divisible | 1,046,782 | 38,656 |
| expanding | 64 | 1 | scan | 141,379 | 10,976 |
| expanding | 64 | 1 | divisible | 131,976 | 10,976 |
| expanding | 64 | 8 | scan | 1,143,614 | 87,808 |
| expanding | 64 | 8 | divisible | 1,068,390 | 87,808 |
| shrinking | 64 | 1 | scan | 131,526 | 4,832 |
| shrinking | 64 | 1 | divisible | 131,595 | 4,832 |
| shrinking | 64 | 8 | scan | 1,054,422 | 38,656 |
| shrinking | 64 | 8 | divisible | 1,054,974 | 38,656 |
| variable | 64 | 1 | scan | 132,230 | 4,832 |
| variable | 64 | 1 | divisible | 132,299 | 4,832 |
| variable | 64 | 8 | scan | 1,060,054 | 38,656 |
| variable | 64 | 8 | divisible | 1,060,606 | 38,656 |
| sparse | 64 | 1 | scan | 91,934 | 4,832 |
| sparse | 64 | 1 | divisible | 82,531 | 4,832 |
| sparse | 64 | 8 | scan | 737,686 | 38,656 |
| sparse | 64 | 8 | divisible | 662,462 | 38,656 |
| unused | 64 | 1 | scan | 77,095 | 192 |
| unused | 64 | 1 | divisible | 67,692 | 192 |
| unused | 64 | 8 | scan | 616,478 | 1,536 |
| unused | 64 | 8 | divisible | 541,254 | 1,536 |
| underestimate | 17 | 1 | scan | 36,997 | 1,472 |
| underestimate | 17 | 1 | divisible | 38,429 | 5,120 |
| underestimate | 64 | 1 | scan | 133,126 | 4,832 |
| underestimate | 64 | 1 | divisible | 133,195 | 4,832 |
| underestimate | 64 | 8 | scan | 1,067,222 | 38,656 |
| underestimate | 64 | 8 | divisible | 1,067,774 | 38,656 |
| overestimate | 64 | 1 | scan | 133,126 | 4,832 |
| overestimate | 64 | 1 | divisible | 124,715 | 9,440 |
| overestimate | 64 | 8 | scan | 1,067,222 | 38,656 |
| overestimate | 64 | 8 | divisible | 1,006,956 | 75,520 |

## All measurements

| Workload | Blocks | Executions | Strategy | Input bytes | Output bytes | Gas | Memory bytes |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |
| equal | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| equal | 0 | 1 | lazy | 0 | 0 | 1,004 | 192 |
| equal | 0 | 1 | bytes1x | 0 | 0 | 1,176 | 192 |
| equal | 0 | 1 | bytes2x | 0 | 0 | 1,176 | 192 |
| equal | 0 | 1 | bytes4x | 0 | 0 | 1,176 | 192 |
| equal | 0 | 1 | divisible | 0 | 0 | 1,644 | 192 |
| equal | 1 | 1 | scan | 72 | 72 | 4,388 | 320 |
| equal | 1 | 1 | lazy | 72 | 72 | 3,753 | 352 |
| equal | 1 | 1 | bytes1x | 72 | 72 | 3,652 | 320 |
| equal | 1 | 1 | bytes2x | 72 | 72 | 3,664 | 384 |
| equal | 1 | 1 | bytes4x | 72 | 72 | 3,688 | 512 |
| equal | 1 | 1 | divisible | 72 | 72 | 4,120 | 320 |
| equal | 8 | 1 | scan | 576 | 576 | 19,445 | 800 |
| equal | 8 | 1 | lazy | 576 | 576 | 20,010 | 2,336 |
| equal | 8 | 1 | bytes1x | 576 | 576 | 17,694 | 800 |
| equal | 8 | 1 | bytes2x | 576 | 576 | 17,805 | 1,376 |
| equal | 8 | 1 | bytes4x | 576 | 576 | 18,030 | 2,528 |
| equal | 8 | 1 | divisible | 576 | 576 | 18,162 | 800 |
| equal | 17 | 1 | scan | 1,224 | 1,224 | 38,816 | 1,472 |
| equal | 17 | 1 | lazy | 1,224 | 1,224 | 39,082 | 4,448 |
| equal | 17 | 1 | bytes1x | 1,224 | 1,224 | 35,760 | 1,472 |
| equal | 17 | 1 | bytes2x | 1,224 | 1,224 | 35,999 | 2,688 |
| equal | 17 | 1 | bytes4x | 1,224 | 1,224 | 36,492 | 5,120 |
| equal | 17 | 1 | divisible | 1,224 | 1,224 | 36,228 | 1,472 |
| equal | 64 | 1 | scan | 4,608 | 4,608 | 139,974 | 4,832 |
| equal | 64 | 1 | lazy | 4,608 | 4,608 | 137,389 | 16,864 |
| equal | 64 | 1 | bytes1x | 4,608 | 4,608 | 130,103 | 4,832 |
| equal | 64 | 1 | bytes2x | 4,608 | 4,608 | 131,095 | 9,440 |
| equal | 64 | 1 | bytes4x | 4,608 | 4,608 | 133,321 | 18,656 |
| equal | 64 | 1 | divisible | 4,608 | 4,608 | 130,571 | 4,832 |
| equal | 64 | 8 | scan | 4,608 | 4,608 | 1,122,006 | 38,656 |
| equal | 64 | 8 | lazy | 4,608 | 4,608 | 1,129,207 | 134,912 |
| equal | 64 | 8 | bytes1x | 4,608 | 4,608 | 1,043,038 | 38,656 |
| equal | 64 | 8 | bytes2x | 4,608 | 4,608 | 1,057,996 | 75,520 |
| equal | 64 | 8 | bytes4x | 4,608 | 4,608 | 1,103,464 | 149,248 |
| equal | 64 | 8 | divisible | 4,608 | 4,608 | 1,046,782 | 38,656 |
| equal | 256 | 1 | scan | 18,432 | 18,432 | 553,688 | 18,656 |
| equal | 256 | 1 | lazy | 18,432 | 18,432 | 540,640 | 66,144 |
| equal | 256 | 1 | bytes1x | 18,432 | 18,432 | 515,977 | 18,656 |
| equal | 256 | 1 | bytes2x | 18,432 | 18,432 | 521,402 | 37,088 |
| equal | 256 | 1 | bytes4x | 18,432 | 18,432 | 536,140 | 73,952 |
| equal | 256 | 1 | divisible | 18,432 | 18,432 | 516,445 | 18,656 |
| expanding | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| expanding | 0 | 1 | lazy | 0 | 0 | 1,004 | 192 |
| expanding | 0 | 1 | bytes1x | 0 | 0 | 1,176 | 192 |
| expanding | 0 | 1 | bytes2x | 0 | 0 | 1,176 | 192 |
| expanding | 0 | 1 | bytes4x | 0 | 0 | 1,176 | 192 |
| expanding | 0 | 1 | divisible | 0 | 0 | 1,644 | 192 |
| expanding | 1 | 1 | scan | 72 | 168 | 4,407 | 416 |
| expanding | 1 | 1 | lazy | 72 | 168 | 3,911 | 480 |
| expanding | 1 | 1 | bytes1x | 72 | 168 | 4,054 | 512 |
| expanding | 1 | 1 | bytes2x | 72 | 168 | 3,921 | 512 |
| expanding | 1 | 1 | bytes4x | 72 | 168 | 3,689 | 512 |
| expanding | 1 | 1 | divisible | 72 | 168 | 4,139 | 416 |
| expanding | 8 | 1 | scan | 576 | 1,344 | 19,601 | 1,568 |
| expanding | 8 | 1 | lazy | 576 | 1,344 | 20,620 | 4,256 |
| expanding | 8 | 1 | bytes1x | 576 | 1,344 | 19,785 | 4,384 |
| expanding | 8 | 1 | bytes2x | 576 | 1,344 | 18,992 | 3,744 |
| expanding | 8 | 1 | bytes4x | 576 | 1,344 | 18,038 | 2,528 |
| expanding | 8 | 1 | divisible | 576 | 1,344 | 18,318 | 1,568 |
| expanding | 17 | 1 | scan | 1,224 | 2,856 | 39,154 | 3,104 |
| expanding | 17 | 1 | lazy | 1,224 | 2,856 | 40,253 | 8,416 |
| expanding | 17 | 1 | bytes1x | 1,224 | 2,856 | 38,897 | 8,960 |
| expanding | 17 | 1 | bytes2x | 1,224 | 2,856 | 37,883 | 7,648 |
| expanding | 17 | 1 | bytes4x | 1,224 | 2,856 | 36,509 | 5,120 |
| expanding | 17 | 1 | divisible | 1,224 | 2,856 | 36,566 | 3,104 |
| expanding | 64 | 1 | scan | 4,608 | 10,752 | 141,379 | 10,976 |
| expanding | 64 | 1 | lazy | 4,608 | 10,752 | 142,936 | 33,120 |
| expanding | 64 | 1 | bytes1x | 4,608 | 10,752 | 139,881 | 32,608 |
| expanding | 64 | 1 | bytes2x | 4,608 | 10,752 | 137,422 | 27,936 |
| expanding | 64 | 1 | bytes4x | 4,608 | 10,752 | 133,385 | 18,656 |
| expanding | 64 | 1 | divisible | 4,608 | 10,752 | 131,976 | 10,976 |
| expanding | 64 | 8 | scan | 4,608 | 10,752 | 1,143,614 | 87,808 |
| expanding | 64 | 8 | lazy | 4,608 | 10,752 | 1,260,369 | 264,960 |
| expanding | 64 | 8 | bytes1x | 4,608 | 10,752 | 1,232,331 | 260,864 |
| expanding | 64 | 8 | bytes2x | 4,608 | 10,752 | 1,182,448 | 223,488 |
| expanding | 64 | 8 | bytes4x | 4,608 | 10,752 | 1,103,976 | 149,248 |
| expanding | 64 | 8 | divisible | 4,608 | 10,752 | 1,068,390 | 87,808 |
| expanding | 256 | 1 | scan | 18,432 | 43,008 | 561,465 | 43,232 |
| expanding | 256 | 1 | lazy | 18,432 | 43,008 | 581,036 | 131,552 |
| expanding | 256 | 1 | bytes1x | 18,432 | 43,008 | 574,708 | 129,376 |
| expanding | 256 | 1 | bytes2x | 18,432 | 43,008 | 560,421 | 110,880 |
| expanding | 256 | 1 | bytes4x | 18,432 | 43,008 | 536,396 | 73,952 |
| expanding | 256 | 1 | divisible | 18,432 | 43,008 | 524,222 | 43,232 |
| shrinking | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| shrinking | 0 | 1 | lazy | 0 | 0 | 1,004 | 192 |
| shrinking | 0 | 1 | bytes1x | 0 | 0 | 1,176 | 192 |
| shrinking | 0 | 1 | bytes2x | 0 | 0 | 1,176 | 192 |
| shrinking | 0 | 1 | bytes4x | 0 | 0 | 1,176 | 192 |
| shrinking | 0 | 1 | divisible | 0 | 0 | 1,644 | 192 |
| shrinking | 1 | 1 | scan | 264 | 72 | 4,256 | 320 |
| shrinking | 1 | 1 | lazy | 264 | 72 | 3,621 | 352 |
| shrinking | 1 | 1 | bytes1x | 264 | 72 | 3,556 | 512 |
| shrinking | 1 | 1 | bytes2x | 264 | 72 | 3,605 | 768 |
| shrinking | 1 | 1 | bytes4x | 264 | 72 | 3,703 | 1,280 |
| shrinking | 1 | 1 | divisible | 264 | 72 | 4,325 | 320 |
| shrinking | 8 | 1 | scan | 2,112 | 576 | 18,389 | 800 |
| shrinking | 8 | 1 | lazy | 2,112 | 576 | 18,954 | 2,336 |
| shrinking | 8 | 1 | bytes1x | 2,112 | 576 | 16,936 | 2,336 |
| shrinking | 8 | 1 | bytes2x | 2,112 | 576 | 17,360 | 4,448 |
| shrinking | 8 | 1 | bytes4x | 2,112 | 576 | 18,260 | 8,672 |
| shrinking | 8 | 1 | divisible | 2,112 | 576 | 18,458 | 800 |
| shrinking | 17 | 1 | scan | 4,488 | 1,224 | 36,572 | 1,472 |
| shrinking | 17 | 1 | lazy | 4,488 | 1,224 | 36,838 | 4,448 |
| shrinking | 17 | 1 | bytes1x | 4,488 | 1,224 | 34,169 | 4,736 |
| shrinking | 17 | 1 | bytes2x | 4,488 | 1,224 | 35,130 | 9,216 |
| shrinking | 17 | 1 | bytes4x | 4,488 | 1,224 | 37,283 | 18,176 |
| shrinking | 17 | 1 | divisible | 4,488 | 1,224 | 34,210 | 2,624 |
| shrinking | 64 | 1 | scan | 16,896 | 4,608 | 131,526 | 4,832 |
| shrinking | 64 | 1 | lazy | 16,896 | 4,608 | 128,941 | 16,864 |
| shrinking | 64 | 1 | bytes1x | 16,896 | 4,608 | 124,480 | 17,120 |
| shrinking | 64 | 1 | bytes2x | 16,896 | 4,608 | 129,304 | 34,016 |
| shrinking | 64 | 1 | bytes4x | 16,896 | 4,608 | 142,219 | 67,808 |
| shrinking | 64 | 1 | divisible | 16,896 | 4,608 | 131,595 | 4,832 |
| shrinking | 64 | 8 | scan | 16,896 | 4,608 | 1,054,422 | 38,656 |
| shrinking | 64 | 8 | lazy | 16,896 | 4,608 | 1,061,623 | 134,912 |
| shrinking | 64 | 8 | bytes1x | 16,896 | 4,608 | 1,026,862 | 136,960 |
| shrinking | 64 | 8 | bytes2x | 16,896 | 4,608 | 1,157,740 | 272,128 |
| shrinking | 64 | 8 | bytes4x | 16,896 | 4,608 | 1,628,584 | 542,464 |
| shrinking | 64 | 8 | divisible | 16,896 | 4,608 | 1,054,974 | 38,656 |
| shrinking | 256 | 1 | scan | 67,584 | 18,432 | 519,896 | 18,656 |
| shrinking | 256 | 1 | lazy | 67,584 | 18,432 | 506,848 | 66,144 |
| shrinking | 256 | 1 | bytes1x | 67,584 | 18,432 | 499,531 | 67,808 |
| shrinking | 256 | 1 | bytes2x | 67,584 | 18,432 | 538,430 | 135,392 |
| shrinking | 256 | 1 | bytes4x | 67,584 | 18,432 | 668,500 | 270,560 |
| shrinking | 256 | 1 | divisible | 67,584 | 18,432 | 519,965 | 18,656 |
| variable | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| variable | 0 | 1 | lazy | 0 | 0 | 1,004 | 192 |
| variable | 0 | 1 | bytes1x | 0 | 0 | 1,176 | 192 |
| variable | 0 | 1 | bytes2x | 0 | 0 | 1,176 | 192 |
| variable | 0 | 1 | bytes4x | 0 | 0 | 1,176 | 192 |
| variable | 0 | 1 | divisible | 0 | 0 | 1,644 | 192 |
| variable | 1 | 1 | scan | 8 | 72 | 4,267 | 320 |
| variable | 1 | 1 | lazy | 8 | 72 | 3,632 | 352 |
| variable | 1 | 1 | bytes1x | 8 | 72 | 4,168 | 352 |
| variable | 1 | 1 | bytes2x | 8 | 72 | 4,035 | 352 |
| variable | 1 | 1 | bytes4x | 8 | 72 | 3,902 | 352 |
| variable | 1 | 1 | divisible | 8 | 72 | 4,336 | 320 |
| variable | 8 | 1 | scan | 4,704 | 576 | 18,477 | 800 |
| variable | 8 | 1 | lazy | 4,704 | 576 | 19,042 | 2,336 |
| variable | 8 | 1 | bytes1x | 4,704 | 576 | 17,547 | 4,928 |
| variable | 8 | 1 | bytes2x | 4,704 | 576 | 18,562 | 9,632 |
| variable | 8 | 1 | bytes4x | 4,704 | 576 | 20,845 | 19,040 |
| variable | 8 | 1 | divisible | 4,704 | 576 | 18,546 | 800 |
| variable | 17 | 1 | scan | 9,416 | 1,224 | 36,759 | 1,472 |
| variable | 17 | 1 | lazy | 9,416 | 1,224 | 37,025 | 4,448 |
| variable | 17 | 1 | bytes1x | 9,416 | 1,224 | 35,417 | 9,664 |
| variable | 17 | 1 | bytes2x | 9,416 | 1,224 | 37,702 | 19,072 |
| variable | 17 | 1 | bytes4x | 9,416 | 1,224 | 43,283 | 37,888 |
| variable | 17 | 1 | divisible | 9,416 | 1,224 | 36,828 | 1,472 |
| variable | 64 | 1 | scan | 37,632 | 4,608 | 132,230 | 4,832 |
| variable | 64 | 1 | lazy | 37,632 | 4,608 | 129,645 | 16,864 |
| variable | 64 | 1 | bytes1x | 37,632 | 4,608 | 131,256 | 37,856 |
| variable | 64 | 1 | bytes2x | 37,632 | 4,608 | 146,466 | 75,488 |
| variable | 64 | 1 | bytes4x | 37,632 | 4,608 | 193,093 | 150,752 |
| variable | 64 | 1 | divisible | 37,632 | 4,608 | 132,299 | 4,832 |
| variable | 64 | 8 | scan | 37,632 | 4,608 | 1,060,054 | 38,656 |
| variable | 64 | 8 | lazy | 37,632 | 4,608 | 1,067,255 | 134,912 |
| variable | 64 | 8 | bytes1x | 37,632 | 4,608 | 1,202,837 | 302,848 |
| variable | 64 | 8 | bytes2x | 37,632 | 4,608 | 1,780,106 | 603,904 |
| variable | 64 | 8 | bytes4x | 37,632 | 4,608 | 3,971,876 | 1,206,016 |
| variable | 64 | 8 | divisible | 37,632 | 4,608 | 1,060,606 | 38,656 |
| variable | 256 | 1 | scan | 150,528 | 18,432 | 522,712 | 18,656 |
| variable | 256 | 1 | lazy | 150,528 | 18,432 | 509,664 | 66,144 |
| variable | 256 | 1 | bytes1x | 150,528 | 18,432 | 552,517 | 150,752 |
| variable | 256 | 1 | bytes2x | 150,528 | 18,432 | 710,597 | 301,280 |
| variable | 256 | 1 | bytes4x | 150,528 | 18,432 | 1,286,065 | 602,336 |
| variable | 256 | 1 | divisible | 150,528 | 18,432 | 522,781 | 18,656 |
| sparse | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| sparse | 0 | 1 | lazy | 0 | 0 | 1,004 | 192 |
| sparse | 0 | 1 | bytes1x | 0 | 0 | 1,176 | 192 |
| sparse | 0 | 1 | bytes2x | 0 | 0 | 1,176 | 192 |
| sparse | 0 | 1 | bytes4x | 0 | 0 | 1,176 | 192 |
| sparse | 0 | 1 | divisible | 0 | 0 | 1,644 | 192 |
| sparse | 1 | 1 | scan | 72 | 72 | 4,452 | 320 |
| sparse | 1 | 1 | lazy | 72 | 72 | 3,817 | 352 |
| sparse | 1 | 1 | bytes1x | 72 | 72 | 3,716 | 320 |
| sparse | 1 | 1 | bytes2x | 72 | 72 | 3,728 | 384 |
| sparse | 1 | 1 | bytes4x | 72 | 72 | 3,752 | 512 |
| sparse | 1 | 1 | divisible | 72 | 72 | 4,184 | 320 |
| sparse | 8 | 1 | scan | 576 | 72 | 13,440 | 800 |
| sparse | 8 | 1 | lazy | 576 | 72 | 11,699 | 352 |
| sparse | 8 | 1 | bytes1x | 576 | 72 | 11,689 | 800 |
| sparse | 8 | 1 | bytes2x | 576 | 72 | 11,800 | 1,376 |
| sparse | 8 | 1 | bytes4x | 576 | 72 | 12,025 | 2,528 |
| sparse | 8 | 1 | divisible | 576 | 72 | 12,157 | 800 |
| sparse | 17 | 1 | scan | 1,224 | 216 | 26,870 | 1,472 |
| sparse | 17 | 1 | lazy | 1,224 | 216 | 24,380 | 672 |
| sparse | 17 | 1 | bytes1x | 1,224 | 216 | 23,814 | 1,472 |
| sparse | 17 | 1 | bytes2x | 1,224 | 216 | 24,053 | 2,688 |
| sparse | 17 | 1 | bytes4x | 1,224 | 216 | 24,546 | 5,120 |
| sparse | 17 | 1 | divisible | 1,224 | 216 | 24,282 | 1,472 |
| sparse | 64 | 1 | scan | 4,608 | 576 | 91,934 | 4,832 |
| sparse | 64 | 1 | lazy | 4,608 | 576 | 83,578 | 2,336 |
| sparse | 64 | 1 | bytes1x | 4,608 | 576 | 82,063 | 4,832 |
| sparse | 64 | 1 | bytes2x | 4,608 | 576 | 83,055 | 9,440 |
| sparse | 64 | 1 | bytes4x | 4,608 | 576 | 85,281 | 18,656 |
| sparse | 64 | 1 | divisible | 4,608 | 576 | 82,531 | 4,832 |
| sparse | 64 | 8 | scan | 4,608 | 576 | 737,686 | 38,656 |
| sparse | 64 | 8 | lazy | 4,608 | 576 | 668,924 | 18,688 |
| sparse | 64 | 8 | bytes1x | 4,608 | 576 | 658,718 | 38,656 |
| sparse | 64 | 8 | bytes2x | 4,608 | 576 | 673,676 | 75,520 |
| sparse | 64 | 8 | bytes4x | 4,608 | 576 | 719,144 | 149,248 |
| sparse | 64 | 8 | divisible | 4,608 | 576 | 662,462 | 38,656 |
| sparse | 256 | 1 | scan | 18,432 | 2,304 | 361,528 | 18,656 |
| sparse | 256 | 1 | lazy | 18,432 | 2,304 | 324,939 | 8,608 |
| sparse | 256 | 1 | bytes1x | 18,432 | 2,304 | 323,817 | 18,656 |
| sparse | 256 | 1 | bytes2x | 18,432 | 2,304 | 329,242 | 37,088 |
| sparse | 256 | 1 | bytes4x | 18,432 | 2,304 | 343,980 | 73,952 |
| sparse | 256 | 1 | divisible | 18,432 | 2,304 | 324,285 | 18,656 |
| unused | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| unused | 0 | 1 | lazy | 0 | 0 | 1,004 | 192 |
| unused | 0 | 1 | bytes1x | 0 | 0 | 1,176 | 192 |
| unused | 0 | 1 | bytes2x | 0 | 0 | 1,176 | 192 |
| unused | 0 | 1 | bytes4x | 0 | 0 | 1,176 | 192 |
| unused | 0 | 1 | divisible | 0 | 0 | 1,644 | 192 |
| unused | 1 | 1 | scan | 72 | 0 | 2,944 | 192 |
| unused | 1 | 1 | lazy | 72 | 0 | 2,036 | 192 |
| unused | 1 | 1 | bytes1x | 72 | 0 | 2,208 | 192 |
| unused | 1 | 1 | bytes2x | 72 | 0 | 2,208 | 192 |
| unused | 1 | 1 | bytes4x | 72 | 0 | 2,208 | 192 |
| unused | 1 | 1 | divisible | 72 | 0 | 2,676 | 192 |
| unused | 8 | 1 | scan | 576 | 0 | 11,183 | 192 |
| unused | 8 | 1 | lazy | 576 | 0 | 9,260 | 192 |
| unused | 8 | 1 | bytes1x | 576 | 0 | 9,432 | 192 |
| unused | 8 | 1 | bytes2x | 576 | 0 | 9,432 | 192 |
| unused | 8 | 1 | bytes4x | 576 | 0 | 9,432 | 192 |
| unused | 8 | 1 | divisible | 576 | 0 | 9,900 | 192 |
| unused | 17 | 1 | scan | 1,224 | 0 | 21,776 | 192 |
| unused | 17 | 1 | lazy | 1,224 | 0 | 18,548 | 192 |
| unused | 17 | 1 | bytes1x | 1,224 | 0 | 18,720 | 192 |
| unused | 17 | 1 | bytes2x | 1,224 | 0 | 18,720 | 192 |
| unused | 17 | 1 | bytes4x | 1,224 | 0 | 18,720 | 192 |
| unused | 17 | 1 | divisible | 1,224 | 0 | 19,188 | 192 |
| unused | 64 | 1 | scan | 4,608 | 0 | 77,095 | 192 |
| unused | 64 | 1 | lazy | 4,608 | 0 | 67,052 | 192 |
| unused | 64 | 1 | bytes1x | 4,608 | 0 | 67,224 | 192 |
| unused | 64 | 1 | bytes2x | 4,608 | 0 | 67,224 | 192 |
| unused | 64 | 1 | bytes4x | 4,608 | 0 | 67,224 | 192 |
| unused | 64 | 1 | divisible | 4,608 | 0 | 67,692 | 192 |
| unused | 64 | 8 | scan | 4,608 | 0 | 616,478 | 1,536 |
| unused | 64 | 8 | lazy | 4,608 | 0 | 536,134 | 1,536 |
| unused | 64 | 8 | bytes1x | 4,608 | 0 | 537,510 | 1,536 |
| unused | 64 | 8 | bytes2x | 4,608 | 0 | 537,510 | 1,536 |
| unused | 64 | 8 | bytes4x | 4,608 | 0 | 537,510 | 1,536 |
| unused | 64 | 8 | divisible | 4,608 | 0 | 541,254 | 1,536 |
| unused | 256 | 1 | scan | 18,432 | 0 | 303,079 | 192 |
| unused | 256 | 1 | lazy | 18,432 | 0 | 265,196 | 192 |
| unused | 256 | 1 | bytes1x | 18,432 | 0 | 265,368 | 192 |
| unused | 256 | 1 | bytes2x | 18,432 | 0 | 265,368 | 192 |
| unused | 256 | 1 | bytes4x | 18,432 | 0 | 265,368 | 192 |
| unused | 256 | 1 | divisible | 18,432 | 0 | 265,836 | 192 |
| underestimate | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| underestimate | 0 | 1 | lazy | 0 | 0 | 1,004 | 192 |
| underestimate | 0 | 1 | bytes1x | 0 | 0 | 1,176 | 192 |
| underestimate | 0 | 1 | bytes2x | 0 | 0 | 1,176 | 192 |
| underestimate | 0 | 1 | bytes4x | 0 | 0 | 1,176 | 192 |
| underestimate | 0 | 1 | divisible | 0 | 0 | 1,644 | 192 |
| underestimate | 1 | 1 | scan | 8 | 72 | 4,281 | 320 |
| underestimate | 1 | 1 | lazy | 8 | 72 | 3,646 | 352 |
| underestimate | 1 | 1 | bytes1x | 8 | 72 | 4,182 | 352 |
| underestimate | 1 | 1 | bytes2x | 8 | 72 | 4,049 | 352 |
| underestimate | 1 | 1 | bytes4x | 8 | 72 | 3,916 | 352 |
| underestimate | 1 | 1 | divisible | 8 | 72 | 4,350 | 320 |
| underestimate | 8 | 1 | scan | 64 | 576 | 18,589 | 800 |
| underestimate | 8 | 1 | lazy | 64 | 576 | 19,154 | 2,336 |
| underestimate | 8 | 1 | bytes1x | 64 | 576 | 19,291 | 2,336 |
| underestimate | 8 | 1 | bytes2x | 64 | 576 | 19,059 | 2,336 |
| underestimate | 8 | 1 | bytes4x | 64 | 576 | 18,397 | 2,144 |
| underestimate | 8 | 1 | divisible | 64 | 576 | 18,658 | 800 |
| underestimate | 17 | 1 | scan | 136 | 1,224 | 36,997 | 1,472 |
| underestimate | 17 | 1 | lazy | 136 | 1,224 | 37,263 | 4,448 |
| underestimate | 17 | 1 | bytes1x | 136 | 1,224 | 37,234 | 4,736 |
| underestimate | 17 | 1 | bytes2x | 136 | 1,224 | 36,564 | 4,512 |
| underestimate | 17 | 1 | bytes4x | 136 | 1,224 | 35,856 | 4,160 |
| underestimate | 17 | 1 | divisible | 136 | 1,224 | 38,429 | 5,120 |
| underestimate | 64 | 1 | scan | 512 | 4,608 | 133,126 | 4,832 |
| underestimate | 64 | 1 | lazy | 512 | 4,608 | 130,541 | 16,864 |
| underestimate | 64 | 1 | bytes1x | 512 | 4,608 | 129,058 | 16,352 |
| underestimate | 64 | 1 | bytes2x | 512 | 4,608 | 128,251 | 15,776 |
| underestimate | 64 | 1 | bytes4x | 512 | 4,608 | 127,272 | 14,688 |
| underestimate | 64 | 1 | divisible | 512 | 4,608 | 133,195 | 4,832 |
| underestimate | 64 | 8 | scan | 512 | 4,608 | 1,067,222 | 38,656 |
| underestimate | 64 | 8 | lazy | 512 | 4,608 | 1,074,423 | 134,912 |
| underestimate | 64 | 8 | bytes1x | 512 | 4,608 | 1,060,737 | 130,816 |
| underestimate | 64 | 8 | bytes2x | 512 | 4,608 | 1,052,307 | 126,208 |
| underestimate | 64 | 8 | bytes4x | 512 | 4,608 | 1,040,937 | 117,504 |
| underestimate | 64 | 8 | divisible | 512 | 4,608 | 1,067,774 | 38,656 |
| underestimate | 256 | 1 | scan | 2,048 | 18,432 | 526,296 | 18,656 |
| underestimate | 256 | 1 | lazy | 2,048 | 18,432 | 513,248 | 66,144 |
| underestimate | 256 | 1 | bytes1x | 2,048 | 18,432 | 509,569 | 63,968 |
| underestimate | 256 | 1 | bytes2x | 2,048 | 18,432 | 507,862 | 61,856 |
| underestimate | 256 | 1 | bytes4x | 2,048 | 18,432 | 505,138 | 57,696 |
| underestimate | 256 | 1 | divisible | 2,048 | 18,432 | 526,365 | 18,656 |
| overestimate | 0 | 1 | scan | 0 | 0 | 1,767 | 192 |
| overestimate | 0 | 1 | lazy | 0 | 0 | 1,004 | 192 |
| overestimate | 0 | 1 | bytes1x | 0 | 0 | 1,176 | 192 |
| overestimate | 0 | 1 | bytes2x | 0 | 0 | 1,176 | 192 |
| overestimate | 0 | 1 | bytes4x | 0 | 0 | 1,176 | 192 |
| overestimate | 0 | 1 | divisible | 0 | 0 | 1,644 | 192 |
| overestimate | 1 | 1 | scan | 272 | 72 | 4,281 | 320 |
| overestimate | 1 | 1 | lazy | 272 | 72 | 3,646 | 352 |
| overestimate | 1 | 1 | bytes1x | 272 | 72 | 3,581 | 512 |
| overestimate | 1 | 1 | bytes2x | 272 | 72 | 3,630 | 768 |
| overestimate | 1 | 1 | bytes4x | 272 | 72 | 3,734 | 1,312 |
| overestimate | 1 | 1 | divisible | 272 | 72 | 4,025 | 384 |
| overestimate | 8 | 1 | scan | 2,176 | 576 | 18,589 | 800 |
| overestimate | 8 | 1 | lazy | 2,176 | 576 | 19,154 | 2,336 |
| overestimate | 8 | 1 | bytes1x | 2,176 | 576 | 17,149 | 2,400 |
| overestimate | 8 | 1 | bytes2x | 2,176 | 576 | 17,587 | 4,576 |
| overestimate | 8 | 1 | bytes4x | 2,176 | 576 | 18,517 | 8,928 |
| overestimate | 8 | 1 | divisible | 2,176 | 576 | 17,417 | 1,376 |
| overestimate | 17 | 1 | scan | 4,624 | 1,224 | 36,997 | 1,472 |
| overestimate | 17 | 1 | lazy | 4,624 | 1,224 | 37,263 | 4,448 |
| overestimate | 17 | 1 | bytes1x | 4,624 | 1,224 | 34,620 | 4,864 |
| overestimate | 17 | 1 | bytes2x | 4,624 | 1,224 | 35,612 | 9,472 |
| overestimate | 17 | 1 | bytes4x | 4,624 | 1,224 | 37,848 | 18,720 |
| overestimate | 17 | 1 | divisible | 4,624 | 1,224 | 34,648 | 2,688 |
| overestimate | 64 | 1 | scan | 17,408 | 4,608 | 133,126 | 4,832 |
| overestimate | 64 | 1 | lazy | 17,408 | 4,608 | 130,541 | 16,864 |
| overestimate | 64 | 1 | bytes1x | 17,408 | 4,608 | 126,210 | 17,632 |
| overestimate | 64 | 1 | bytes2x | 17,408 | 4,608 | 131,231 | 35,040 |
| overestimate | 64 | 1 | bytes4x | 17,408 | 4,608 | 144,742 | 69,856 |
| overestimate | 64 | 1 | divisible | 17,408 | 4,608 | 124,715 | 9,440 |
| overestimate | 64 | 8 | scan | 17,408 | 4,608 | 1,067,222 | 38,656 |
| overestimate | 64 | 8 | lazy | 17,408 | 4,608 | 1,074,423 | 134,912 |
| overestimate | 64 | 8 | bytes1x | 17,408 | 4,608 | 1,042,604 | 141,056 |
| overestimate | 64 | 8 | bytes2x | 17,408 | 4,608 | 1,180,712 | 280,320 |
| overestimate | 64 | 8 | bytes4x | 17,408 | 4,608 | 1,678,880 | 558,848 |
| overestimate | 64 | 8 | divisible | 17,408 | 4,608 | 1,006,956 | 75,520 |
| overestimate | 256 | 1 | scan | 69,632 | 18,432 | 526,296 | 18,656 |
| overestimate | 256 | 1 | lazy | 69,632 | 18,432 | 513,248 | 66,144 |
| overestimate | 256 | 1 | bytes1x | 69,632 | 18,432 | 506,854 | 69,856 |
| overestimate | 256 | 1 | bytes2x | 69,632 | 18,432 | 547,748 | 139,488 |
| overestimate | 256 | 1 | bytes4x | 69,632 | 18,432 | 685,023 | 278,752 |
| overestimate | 256 | 1 | divisible | 69,632 | 18,432 | 494,478 | 37,088 |
