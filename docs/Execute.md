# Execute

`Execute` provides specialized decoding and output writing for local execute adapters, exported
from `Codec.sol`. It replaces the experimental `MemoryBlocks` API. The old
memory-cursor experiment survives only as `test/PreviousMemoryBlocks.sol` for
historical comparisons.

Calldata enters adapters as a packed input cursor; pipeline state stays
`bytes memory`. Fixed-stride loops establish containment once and then use
absolute positions without repacking cursors or repeating bounds checks.

| Primitive | Source / responsibility |
|---|---|
| `bounds(uint cur, uint size)` | Calldata: unpack validated cursor lanes and reject partial blocks |
| `bounds(bytes memory source, uint size)` | Memory: reject partial blocks and expose absolute bounds |
| `unpackNode(abs)` | Calldata NODE, exact header plus one word |
| `unpackAmount(abs)` | Calldata AMOUNT, exact header plus one scalar quantity |
| `unpackAssetAmount(abs)` | Calldata ASSET_AMOUNT, exact header plus two words |
| `unpackBalanceMemory(abs)` | Memory BALANCE, exact header plus two words |
| `unpackPositionMemory(abs)` | Memory POSITION, exact header and an independent struct |
| `allocateBalances(count)` | Exact BALANCE output allocation; returns absolute position and buffer |
| `writeBalance(abs, asset, amount)` | Write one BALANCE inside reserved memory and return the next position |
| `checkBalances(state, inputCur)` | Fused paired BALANCE / BALANCE_CONSTRAINTS stream validation |
| `checkPositions(state, inputCur)` | Fused paired POSITION / POSITION_CONSTRAINTS stream validation |

```solidity
(uint abs, uint end) = Execute.bounds(inputCur, Sizes.AssetAmount);
while (abs < end) {
    (bytes32 asset, uint amount) = Execute.unpackAssetAmount(abs);
    debitAccount(account, asset, amount);
    unchecked { abs += Sizes.AssetAmount; }
}
```

Bounds helpers require a nonzero complete encoded block size, including its
8-byte header. Calldata cursors must already have validated provenance and
current <= end; metadata is ignored. Memory sources must be live Solidity bytes
allocations. Unpackers require containment established for their exact stride.
These are trusted low-level primitives, not general cursor decoders.

Partial tails are rejected before any hook runs. Exact headers are checked per
block without scanning the stream twice. Existing InvalidBlock selectors,
validation order, existing account checks and budget semantics are preserved.
Under the [account validation convention](../README.md#account-validation-convention),
internal adapters and accounting hooks may trust accounts supplied by their callers.
These structural decoding checks do not validate account format, and command
authorization does not validate untrusted input. Commands must validate any
user-supplied accounts before use, returning positions, or forwarding them.

POSITION decoding uses MCOPY into the struct Solidity allocates for the return
value. It copies all five words without aliasing the input, including counterparty.
Hooks can mutate or retain decoded positions. Avoid manually allocating a second
struct: that doubles allocation in this return-value pattern.

The two constraint checkers retain their fused loops. They validate stream sizes,
headers, identifiers and quantities in the same order, without building structs
or rewriting state. Their execute adapters are now thin calls into the library.

## Performance

The following table records the historical decoding migration, before composite
Bootstrap inputs and operation logging. Bootstrap comparisons in these frozen
fixtures retain the old fixed schema. Current composite Bootstrap gas is measured
in `adapter-optimizations.bench.test.ts`. Bootstrap and Debit now
also use exact output allocation; their additional savings are recorded in
[ExecuteOutputPreallocation.md](ExecuteOutputPreallocation.md).

Measured with solc 0.8.35, viaIR, optimizer 200, Cancun, using actual inherited
adapters versus frozen preceding adapters with identical observable hooks.
Tests compare output, budget, hook effects and source-state hashes.

| Adapter | Gas change |
|---|---:|
| Bootstrap, Debit, Credit, Cashout, Authorize | 0 |
| CheckBalance, CheckPosition | 0 |
| Settle | -96 per POSITION |
| Empty streams | 0 |

Cases cover 0, 1, 2, 4, 8 and 16 blocks; Bootstrap also covers chain/other assets
and zero/nonzero assigned funding. These are internal gasleft measurements;
host hook implementations and compiler settings can affect inlining.

After the shared cursor-helper migration, the complete adapter benchmark measures
a fixed +15 gas for CreditAccount and Cashout at every tested count, and +15 for
empty Settle. Other rows remain at or below their frozen baselines. The benchmark
bounds these specific increases at 15 gas rather than asserting that every
adapter still matches the earlier zero-overhead result. These are instrumented
adapter measurements, not a standalone cost for `Cursors.done`.

The scalar unpackers are deliberately small direct-load primitives. Splitting
their loads and header comparison into private helper calls cost extra gas in
the tested adapter layout. No additional generic reader surface is exposed.

Focused tests include logical cursor slices, metadata, partial tails, malformed
headers, hook-error precedence, full-width POSITION fields and allocation/aliasing.

```sh
npm test -- test/execute-blocks.test.ts
npm run bench -- test/execute-blocks.bench.test.ts
```

Bootstrap directly validates one BOOTSTRAP and its final LIST, including exact
lengths and ASSET_AMOUNT stride, then checks every item header during processing.
`Blocks.unpackBootstrapExact` and the stream-oriented `Blocks.unpackBootstrap`
remain available to other callers. Bootstrap reserves returned balances, a
writable log prefix and worst-case log space in one allocation before hooks run.
Only the returned balances count toward output.length; logical padding is cleared.
The private forkLog helper accepts only this reserved layout and copies the
initialized prefix when native funding requires a separate log. Debit continues
to use allocateBalances and writeBalance for an exactly sized output stream. Hooks may allocate between
writes. Counts are bounded by validated source lengths; the helper rejects byte
sizes exceeding uint32.max. See the [output benchmark](ExecuteOutputPreallocation.md).
