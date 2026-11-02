# Repository Instructions

## Solidity NatSpec

- Document production contracts and libraries with `@title` and `@notice`.
- Give functions and constructors a concise `@notice`; use `@dev` for private
  helpers, modifiers, implementation details, assumptions, and revert conditions.
- Document each named parameter with `@param` in declaration order and every
  return value with `@return` in return order, including its name when declared.
- Use `@dev` for constants, internal storage, struct fields, and errors, and
  `@notice` for public getters. Test fixtures need not follow production coverage.
- Omit NatSpec for endpoint `descriptor` and `id` fields, endpoint constructors,
  and internal endpoint constants such as `LOGS`.
- Use consistent block names such as `ASSET_AMOUNT` and `POSITION_CONSTRAINTS`.
  Distinguish complete blocks from payloads, packed cursors from absolute
  positions, memory from calldata, asset units from wei, and validation performed
  by the helper from requirements imposed on its caller or hook implementation.

## Command lanes

- Keep `command(name, state, input, output, flags)` as the single call that shows a
  command's signature in its constructor.
- Take a lane from a `<command><Lane>()` hook (`Lane` is `State`, `Input` or
  `Output`, e.g. `settleState()`, `addPoolInput()`, `swapExactInputOutput()`),
  called inline in `command(...)`, when the lane is more than a single `Specs`
  constant (built with `lane(...)`, `Specs.toVariant(...)` or anything else that
  computes or emits) or when a host may want to refine it. Otherwise write the
  `Specs` constant inline, e.g. `Specs.Position` or `Specs.PositionCounterparty`.
- Declare hooks `internal virtual` with no mutability keyword, even when the
  default only returns a constant: overrides may only tighten mutability, and a
  host override may call `lane(...)`, which emits. An override that returns a
  constant may itself be `pure`.
- The default hook returns the lane the command published before the hook existed,
  so adding a hook never changes an existing host. Add hooks when a host needs one,
  not to every mixin up front; commands whose behaviour the protocol fixes write
  their variant inline.
- An override that replaces a lane description returns its own `lane(...)` without
  calling `super` (otherwise both descriptions are emitted). One that only adds a
  variant wraps `super`, e.g. `Specs.toVariant(super.addPoolInput(), variant)`.
- Specs that the command also reads at run time (for example `schema(...)` results
  used with `exec.enter`) stay immutables, because calling a hook at run time would
  emit its metadata again; refer to the immutable inline in `command(...)`.
- Variants (`Variants`, spec bits 63-32) are declarations for offchain tools only.
  Do not read or enforce them onchain; only the protocol defines variant keys.

## Development verification

- During local development, run only focused tests for affected behavior, such as
  `npm test -- test/<name>.test.ts`. Batch related edits before verifying them;
  do not run the entire suite after each change or merely to finish a turn.
- Run `npm run typecheck` when relevant to the changes.
- Run benchmarks explicitly with `npm run bench`, or select an affected benchmark
  with `npm run bench -- test/<name>.bench.test.ts`. Use them for gas/performance
  changes, baseline updates, and release verification, not every routine edit.
- Run `npm run typecheck` and the full regular suite (`npm test`) at an agreed
  completion checkpoint for a batch of work, or when explicitly requested.
  `npm test` excludes `*.bench.test.ts` suites.
- Run `npm run test:all` for full verification, including benchmarks, before a release.
- New benchmark suites must use the `*.bench.test.ts` filename convention.
- Keep permanent benchmarks limited to the core production workloads listed in
  README.md. Prefer extending those suites over adding another benchmark file.
  Remove one-off comparison suites and unused candidate fixtures after an
  experiment; preserve useful production correctness cases as regular tests.
- Keep gas-only comparisons in benchmarks. Regular tests may still assert
  functional gas-limit behavior, such as successful recovery after an out-of-gas call.

## Releases

Use this complete flow for every release:

1. Review everything for release readiness.
2. Resolve inconsistencies and run all verification.
3. Split the implementation into logical commits by concern.
4. Move `Unreleased` in `CHANGELOG.md` into the new version section.
5. Update the version in `package.json` and `package-lock.json`.
6. Create a final release commit.
7. Create the annotated version tag.
8. Push the commits and tag to `main`.

Do not publish releases to npm. In particular, do not run `npm publish` or
`npm run publish:package` as part of or after this release process.
