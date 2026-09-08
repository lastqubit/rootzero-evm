# Portal forwarding gas reserve

`Portal.forward` uses `forwardGas` to keep gas for recovery before attempting
the commander's pipe. The helper returns the call budget, or zero to skip delivery.
If there is no pipe budget left, it skips delivery and
attempts to hash and store the message directly. If even recording cannot finish,
the transaction reverts and storage, value transfers, and events roll back.

The fixed `gasReserve` defaults to 35,000. Derived constructors may assign a higher
value to allow for transport work after `forward`. The helper adds variable costs:

```text
words    = (message.length + 31) / 32
endWords = (freeMemoryPointer + 68 + 32 * words + 32 + 31) / 32
reserve  = gasReserve + 12 * words + 3 * endWords + endWords * endWords / 512
           + (value != 0 ? 9_000 : 0)
```

All divisions round down. The word charge covers two calldata copies and hashing.
The memory term includes the ABI header and trailing zero write, conservatively
charging full memory cost even when some memory was already paid for. The fixed
allowance covers cold account access, fresh digest storage, the event, fixed
instructions, and margin. Value overhead assumes an existing commander contract.

The gas snapshot is taken after calculating the reserve. The helper's copying and
CALL costs are paid between that snapshot and entry into the pipe; they therefore
must be included in the reserve, alongside the fallback after CALL.

## Verification

```sh
npx hardhat test test/portal-gas.bench.test.ts test/portal-reserve.bench.test.ts test/portal.test.ts
```

Both benchmarks now call production `Portal.forward`. The pipe attempts to return
4 GiB of memory, causing a real out-of-gas halt. Traces verify the explicit gas
budget reaches the child, including the value stipend, so successful recovery
does not accidentally depend on a larger EIP-150 reserve.

The reserve benchmark covers 32 cases: message sizes 0, 1, 31, 32, 33, 256, 4,096,
and 65,536; zero/nonzero value; and zero/65,536 bytes of prior memory allocation.
Each case uses a fresh cold storage slot and checks the digest and event.

Measured with solc 0.8.35, optimizer 200 runs, Cancun compiler target, and the
repository's default Hardhat simulated L1 execution hardfork:

| Message bytes | Required reserve, zero value | Reserved, zero value | Reserved, nonzero value |
| ---: | ---: | ---: | ---: |
| 0 | 27,116 | 35,027 | 44,027 |
| 256 | 27,236 | 35,147 | 44,147 |
| 4,096 | 29,072 | 36,983 | 45,983 |
| 65,536 | 66,100 | 74,011 | 83,011 |

These rows have no prior transport allocation, apart from the fixture's empty
bytes array. All cases finish with at least 7,911 gas left. More transport work
needs its own allowance; this margin does not fund arbitrary storage writes.
Results are saved to `.npm-cache/portal-reserve-results.json`.

The boundary benchmark writes `.npm-cache/portal-gas-results.json`. It checks
fresh, overwritten, and unchanged digests and records whether the pipe was
attempted. Separate tests cover retained ETH, direct storage without calling the
pipe, insufficient gas even for storage, and a derived constructor's extra reserve.

## Delivery budgets

Gas estimation may select a cheaper successful path that skips the pipe and stores
the message. A successful transaction does not guarantee delivery: callers that
require an attempt must provide a gas budget covering the pipe and reserve, and
observe `Unresolved` to detect messages awaiting recovery.

Previously, forwarding all available gas left only the EIP-150 reserve after pipe
out-of-gas: a fresh 256-byte message needed about 1.58 million transaction gas.
The new reserve protects recovery at 200,000 transaction gas even with attached
ETH. Large-message transaction budgets still include calldata gas charges.

Exact costs depend on compiled code, memory usage, and the execution gas schedule.
Recheck the benchmarks when these change.
