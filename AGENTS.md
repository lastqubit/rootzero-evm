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
