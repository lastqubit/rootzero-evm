# Repository Instructions

## Development verification

- Run focused tests for affected behavior during development. `npm test` runs
  regular tests and excludes `*.bench.test.ts` suites.
- Run benchmarks explicitly with `npm run bench`, or select an affected benchmark
  with `npm run bench -- test/<name>.bench.test.ts`. Use them for gas/performance
  changes, baseline updates, and release verification, not every routine edit.
- Run `npm run typecheck` and `npm test` for ordinary final verification.
- Run `npm run test:all` for full verification, including benchmarks, before a release.
- New benchmark suites must use the `*.bench.test.ts` filename convention.

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
