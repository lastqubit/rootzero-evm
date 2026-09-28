# Named unpacker composition

Solidity 0.8.35, viaIR, optimizer 200, Cancun. The composed BALANCE implementation
is now adopted in Blocks; named fixed-word wrappers use a/b temporaries for casts.

`test/unpack-composition.bench.test.ts` compares dedicated header validation,
cursor advancement, and calldata loads with named wrappers over `unpack64`
(AMOUNT and BALANCE) and `unpack160` (POSITION). AMOUNT and POSITION use the
current named helpers; BALANCE includes the composed candidate and the current
production helper as controls against the frozen direct implementation. Both paths validate the header and
bounds once and return the same updated packed cursor.

Identical consumer harnesses accumulate all fields and pass each returned cursor
directly into the next loop iteration. Cursors retain metadata. Tests also compare
logical truncation rejection and wrong-key errors.

| Block | Count | Direct loop gas | Composed loop gas | Difference |
| --- | ---: | ---: | ---: | ---: |
| AMOUNT / BALANCE | 1 | 226 | 226 | 0 |
| AMOUNT / BALANCE | 4 | 703 | 703 | 0 |
| AMOUNT / BALANCE | 16 | 2,611 | 2,611 | 0 |
| AMOUNT / BALANCE | 128 | 20,419 | 20,419 | 0 |
| POSITION | 1 | 274 | 274 | 0 |
| POSITION | 4 | 895 | 895 | 0 |
| POSITION | 16 | 3,379 | 3,379 | 0 |
| POSITION | 128 | 26,563 | 26,563 | 0 |

These figures include loop/checksum overhead, not just the decoder primitive.
Executable deployed bytecode is identical within each pair after stripping the
compiler metadata trailer: 310 bytes for AMOUNT/BALANCE and 329 for POSITION.
The optimizer removes the abstraction and constant header construction in these
callers. Larger consumers or different compiler settings can change inlining;
these measurements do not guarantee identical results in every caller.

Run `npm run bench -- test/unpack-composition.bench.test.ts`.
Raw results are written to `.npm-cache/unpack-composition-results.json`.
