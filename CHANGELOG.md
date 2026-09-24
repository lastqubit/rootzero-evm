# Changelog

Until the protocol reaches integration-stable status, minor versions may include
breaking API changes. Breaking changes are called out explicitly.

Add all changes made after a release to `Unreleased`. Published version
sections are immutable and must continue to describe the tagged release.

## Unreleased

## 1.44.0

### Added

- Add ASSET_LIMITS (asset, min, max) and POSITION_LIMITS (asset, minAmount,
  liability, maxDebt) schemas with full-width inclusive bounds. Constraints are
  encoded offchain; scalar readers and Blocks/Executions expectation helpers
  provide onchain decoding and validation.
- Add CheckBalance and CheckPosition commands and their Execute adapters,
  exported through Endpoints.sol. Checks preserve state; Execute adapters
  validate memory state directly against calldata without unpacking or copying.
- Add Blocks.descend and Executions.descend to enter a parent and its first
  child, returning child payload and child/parent end positions. Callers remain
  responsible for containment and complete consumption.

### Breaking Changes

- Replace packed QUOTE limits with full-width amount and debt. The layout is now
  (asset, amount, liability, debt), with a 128-byte payload. Quote remains an
  independent schema; use POSITION_LIMITS to constrain a resulting position.
- Remove LIMITS input and quantity checks from realize; input must be empty.
  Compose checkPosition after realization to enforce outcome constraints in
  the same atomic pipeline.
- Rename Blocks.require1/2/4/8/16/32 to expect1/2/4/8/16/32 and requireLimits
  to expectLimits in Blocks and Executions.
- Remove the unused Positions library and its Utils.sol export, and remove
  unpackLimitedPosition from Blocks, Memory, and Executions. Use expectation
  helpers or validation commands instead.
- Move optional schema names into a leading name: prefix in the schema body.
  Remove the separate name argument and decoder return value. SCHEMA payloads
  now contain only uint spec and #string as body (40-byte minimum).
- Put the body string first in SchemaAnnot.schema overloads: schema(body, spec),
  schema(body, key, size), and schema(body, key, min, max, hint). Update schema
  producers and consumers together.

### Documentation

- Define packed LIMITS as an inclusive minimum in the high 128 bits and maximum
  in the low 128 bits, with context determining their meaning. Encoding is unchanged.
- Document Quote fields, optional validation pipelines, and repayment behavior.

## 1.43.0

### Breaking Changes

- Replace descriptor-backed `Executions.open` with
  `openContext(exec, descriptor, budget, context)`, centralizing context decoding
  and exact-boundary validation for `openCommand`, `runCommand`, and `runCommandOnce`.

- Rename `Executions.addValue` to `addToBudget` and remove `close(extraCredit)`.
  Add trusted credit to the execution budget before calling `close()`; credit
  added during a batch is available to subsequent iterations. Update the budget
  credit example to use this flow.

- Remove `Executions.unpackBalanceForHost` and `Decoders.unpackBalanceForHost`.
  Build `HostAmount` explicitly by assigning its host and decoding its asset and
  amount with `unpackBalance`, as `Allocate` now does.

- Rename the balance query to `GetBalance` / `GetBalanceHook` in
  `queries/Balance.sol`, with endpoint `getBalance(bytes)` and callback
  `getBalanceOne`. Update imports and callers: the endpoint selector and query ID
  change. Batch behavior and the `getBalance(account, asset)` hook are unchanged.

- Remove `counterparty` from `Quote` and its codec helpers. QUOTE now encodes
  `(bytes32 asset, bytes32 liability, uint limits)` in 96 payload bytes (104 with
  the header); previous four-word encodings are rejected. `Positions.requireQuoted`
  validates asset, liability, and inclusive quantity bounds only. Counterparty
  authorization and backing remain separate host responsibilities; `Position`
  retains its counterparty field.

- Move the free raw-call helpers into the internal `Calls` library, exported
  through `Core.sol`: `rawCall` becomes `Calls.raw`, `rawCallCopy` becomes
  `Calls.rawCopy`, `tryRawCall` becomes `Calls.tryRaw`, `tryRawCallCopy` becomes
  `Calls.tryRawCopy`, and `rawQuery` becomes `Calls.rawQuery`. Update imports and
  call sites. `FailedCall` remains a global error, and the `Executions.rawCall`
  and `Executions.rawCallCopy` names are unchanged.

### Added and Changed

- Update the custom-command examples to use execution runners where
  their lifecycle fits; retain explicit iteration for the list example's batch index.

- Keep the payable pipe port's shared budget in `Execution`, draining it only
  when settling the remainder through `cashin`.

- Add `PortBase.runPort(input, descriptor, callback)` with shared
  native-value budgeting. Migrate ordinary command and port batches to the
  runners, and both relay commands to `runCommandOnce`. Admin authorization flows,
  specialized pipeline adapters, and post-batch pipe settlement remain explicit.
  Use `<endpoint>One` for batch callbacks and `<endpoint>Once` for whole-input
  callbacks so command, port, and query mixins can be inherited together without
  callback signature conflicts.

- Add `QueryBase.runQuery(input, descriptor, callback)` for input-only
  view callbacks and migrate `AssetStatus` and `GetBalance` to it.

- Add `CommandBase.runCommandOnce(context, descriptor, callback)` to invoke
  a callback exactly once, including for empty sources, and reject leftover data
  before returning output and remaining native-value credit.

- Migrate `Burn` to `CommandBase.runCommand` with a per-balance callback.
  Add a benchmark against its previous loop, including gas, runtime size, and
  behavior comparisons; see `docs/BurnRunBenchmark.md`.

- Add `CommandBase.runCommand(context, descriptor, callback)` to open a
  context, process batch items through an internal callback, and finalize output
  and remaining native-value credit.

- Add `Executions.into` overloads for a parent specification or key, returning
  the same execution for chaining alongside the existing `enter` helpers.

- Add `Executions.rawCall` and `rawCallCopy` accepting full-width native value with inline budget
  debiting and returned-credit accounting, returning only decoded output bytes.

## 1.42.0

### Breaking Changes

- Reorganize `Actions` into groups of 16 with reserved gaps. Add lifecycle, membership, and permission actions, including `Add` (4) and `Remove` (5); `Enable`/`Disable` are 6/7. All previous nonzero action IDs change. Indexers must use deployment-specific catalogs; the indexing guide preserves the v1.41.0 mapping.
- Change `Node` and `Guardian` events to carry `uint32 action, uint status` instead of `bool active`, and add `uint32 action` before `Route`'s status. Zero means inactive; nonzero means active with host-defined meaning. Default hosts emit `Authorize`/`Revoke` and `Appoint`/`Dismiss` with status 1/0, including repeated operations. Update event signatures and decoders.
- Rename the asset preimage event and mixin to `AssetPreimage(bytes32 indexed asset, bytes preimage)` and `AssetPreimageEvent`, removing the host argument. Replace `AssetStatusEvent` with `AssetEvent`, emitting `Asset(uint indexed host, bytes32 asset, uint32 action, uint status)`. The `AssetStatus` query is unchanged.
- Replace `NodeAccess.setNode` with independently overridable `authorizeNode`/`revokeNode`, and `GuardianAccess.setGuardian` with `appointGuardian`/`dismissGuardian`. Default implementations preserve identifier validation and update access state and events together.
- Rename `AllowAssets`/`DenyAssets`, their hooks and ports, and callable endpoints to singular `AllowAsset`/`DenyAsset`, `allowAsset`/`denyAsset`, and `portAllowAsset`/`portDenyAsset`. Consolidate their admin definitions in `commands/admin/Asset.sol`; rename the port and query files to `ports/Asset.sol` and `queries/Asset.sol`. Update imports, selectors, endpoint IDs, and allowlists. Block-stream batching is unchanged; the `Assets` utility keeps its name.
- Consolidate `Appoint`/`Dismiss` in `commands/admin/Guardian.sol`. Update deep imports; contract names and callable endpoints are unchanged.

### Added and Changed

- Define shared action semantics: action identifies the operation, while status describes its result. Route membership changes use `Add`/`Remove`; configured routes can use `Enable`/`Disable`. Asset events distinguish creation, deletion, and support changes.
- Export all shared protocol errors through `Core.sol`, `Commands.sol`, `Endpoints.sol`, and `Utils.sol`, including `QueryFailed`, `UnexpectedInput`, and `UnexpectedState`. Add missing annotation helpers and `Quote` to `Commands.sol`, and `Cur`/`Cursors` to `Utils.sol`, with compile-time import coverage.
- Place hook declarations before command, port, and query implementations. Update API documentation and add event ABI, full-width status, repeated-operation, and singular asset endpoint coverage.

## 1.41.0

### Breaking Changes

- Remove the unused `CommandBase.ValueNotAllowed()` error. Internal pipeline adapters return unused assigned value as credit.

- Make `CashoutHook.cashout` abstract and remove its `ChainAsset` and `SpentEvent` inheritance. Hosts must implement payouts and event emission explicitly. Extract `sendChainAsset(account, amount)` into `core/Cash.sol`, exported through `Core.sol` and `Endpoints.sol`, and replace `CashoutFailed()` with the global `SendFailed()` error in `utils/Errors.sol`, also exported through `Utils.sol`. The helper validates EVM accounts and calls recipients even for zero amounts, preserves transfer failure handling, and emits no events. Hooks choose whether to skip zero amounts.

### Added and Changed

- Add `ExecuteAuthorize`, an internal pipeline adapter that reuses the Authorize command ID and enforces admin access with the host as caller. Default host policy requires a self-managed host; pipeline entrypoints must authenticate admin accounts.

- Add `ExecutionCost.executionCost(entity, base, batch)` and the `#executionCost` annotation for advisory command estimates in destination-local execution units, with standard key, spec, schema, and block encoding support.

- Add the argument-free global `QueryFailed()` error and re-export it from `Utils.sol`.

## 1.40.0

### Breaking Changes

- Change `portBook` input to flat ACCOUNT_AMOUNT debit/credit pairs, replacing its custom parent schema with `#input as (debit, credit)` in a Groups annotation on the port ID. Callers must remove the former parent header; incomplete pairs and malformed blocks still revert atomically.

- Remove LIMITS input from `settle` and `settlePayable`; both consume POSITION streams with empty input. `ExecuteSettle` now iterates memory positions directly and rejects nonempty input.

- Position producers are responsible for quantity limits on their final outputs. Callers must remove settlement LIMITS inputs and enforce those constraints upstream; `Realize` retains its output limit checks. Settlement still applies exact quantities and delegates account authorization to its hooks.

### Added and Changed

- Add `RepayHook`, default debt-only `Settlement.repay`, and the `Repay` command. Repayment takes POSITION state and empty input, settles the exact debt through `BookHook`, and emits each position with only debt set to zero. Successful hooks must fulfill the complete debt without mutating the position.

- Add `GroupsAnnot.annotateGroups(commandId, description)` and the `#groups` annotation to describe only grouped state/input/output lanes using alias lists. Grouping remains off-chain metadata; descriptors, decoding, and allocation do not use group counts.

- Add `Buffers.scale` and its `Executions.scaleOutput(numerator, denominator)` adapter to scale the output capacity hint up or down before its first reservation, without changing descriptors or decoding.

- Implement an overridable default `CashoutHook` that transfers native value to `Accounts.addr(account)` and reverts with `CashoutFailed` without copying recipient return data. The hook inherits `ChainAsset` and `SpentEvent` and emits `Spent(account, chainAsset, amount, Actions.Cashout, 0)` after successful transfers. Zero amounts skip validation, transfer, and emission. Hosts remain responsible for funding, authorization, accounting, and reentrancy protection.

- Add `Blocks.requireLimits` and `Executions.requireLimits` to check final amount and debt directly against a calldata LIMITS block. `Realize` uses the execution helper after its hook returns.

- Correct the endpoint descriptor layout in the indexing guide and refresh the settlement gas baseline.

## 1.39.0

### Breaking Changes

- Rename the pipeline-local `Bootstrap` mixin to `ExecuteBootstrap`.

- Rename `Executions.expectAbs` to `expect`, matching the position-checking
  helpers in `Decoders` and `Cursors`.

- Rename `Blocks.expectEmpty` to `Blocks.enterEmpty` and the private
  `expectFixed` helper to `enterFixed`, matching the block-entry helper family.

- Use fixed-size bounds in `ExecuteSettle` instead of a decoder. Partial LIMITS
  blocks now revert with `InvalidBlock`; unmatched complete blocks revert with
  `UnconsumedData` after the paired loop.

- Remove `limits` from the settlement hooks. `Settle` and `SettlePayable` use
  `Executions.unpackLimitedPosition` to consume and check POSITION state against
  LIMITS input before invoking the hook. `ExecuteSettle` uses the memory helper.
  Direct callers of `Settlement.settle` must enforce their own limits.

- Delegate settlement account validation to `debitAccount` and `creditAccount`,
  or a custom `BookHook`. Nonzero counterparties pass through unchanged;
  empty exchanges skip account validation because they invoke no account hooks.

- Remove the `book(bytes)` command and the `Book` / `ExecuteBook` mixins.
  Use `settle` / `ExecuteSettle` with one packed LIMITS block per position,
  including Rootzero-backed positions. Settlement accepts account counterparties
  and applies a literal uint128 debt cap; callers requiring Rootzero backing
  must validate counterparty zero explicitly. `BookHook`, `portBook`, and the
  historical `Actions.Book` event identifier remain available.

- Give QUOTE its own `Quote` struct and four-word payload: `asset`, `liability`,
  `counterparty`, and packed `uint limits`. The high 128 bits hold the minimum
  asset amount and the low 128 bits the literal maximum debt. QUOTE payloads
  shrink from 160 to 128 bytes; codecs and `Positions.requireQuoted` use the new
  type and layout. Identifier checks precede shared `requireLimits` validation.

- Replace the `Limits` struct with packed `uint limits`: high 128 bits are the
  minimum net asset amount; low 128 bits are the maximum fee-inclusive debt.
  Both are literal bounds, without an unlimited sentinel. LIMITS now carries
  `uint limits` in 32 payload bytes instead of two uint words; all LIMITS codec
  helpers take or return the packed scalar. Remove structured
  LIMITS overloads and codec `requireLimits` helpers; use
  `Positions.requireLimits(position, limits)` for inclusive quantity validation.

- Rename `AmountOutOfRange()` to `OutOfRange()`, changing its error selector.
  Ordering read helpers (`readLtAt32`, `readLeAt32`, `readGtAt32`, `readGeAt32`) use
  `OutOfRange()`; equality and inequality reads retain `UnexpectedValue()`.
- Restore default `Settlement.settle` as exact settlement without host fees.
  Producers supply the final net asset receipt and final total debt payment,
  accounting for their own fees before settlement. Limits are still checked
  before transfers, and account policy is enforced by the host's account hooks.
  Zero-counterparty positions book on the active account.
- Remove `repay`, `collect`, and the settlement-specific
  `ZeroFee` error. Settlement routes both exact exchange legs through `BookHook`,
  liability first, without extra host credits or fee deductions.

### Added

- Add `Cursors.bounds(source, size)` for calldata streams, matching the memory
  overload's whole-block length validation and `InvalidBlock` error.

- Add `Memory.unpackLimitedPosition(pos, lim)` for POSITION in
  memory and LIMITS in calldata. It checks headers and packed quantity bounds,
  then copies the position without aliasing its source. Used by `ExecuteSettle`.

- Add `Blocks.unpackLimitedPosition(pos, lim)` to validate POSITION
  and LIMITS headers, check packed bounds directly in calldata, and return the
  position. Callers must establish bounds; `Executions.unpackLimitedPosition`
  supplies bounded state and input positions for settlement commands.

- Add grouped `Blocks.readEqualAt32`, `readNotEqualAt32`, `readLtAt32`, `readLeAt32`,
  `readGtAt32`, and `readGeAt32` helpers to compare words at absolute calldata
  positions. Equality returns the shared value; the other helpers return both
  words in argument order. Ordering comparisons treat words as unsigned integers.

### Changed

- Return unused assigned value as credit from `ExecuteDebitAccount`,
  `ExecuteCreditAccount`, `ExecuteSettle`, and `ExecuteCashout`. Local execution
  accepts assigned value; external command entrypoints remain nonpayable.

- Accept empty batches in `ExecuteDebitAccount`, `ExecuteCreditAccount`, and
  `ExecuteSettle`, matching their regular commands. Schema, partial-block,
  and paired-stream checks still apply.

- Standardize full-header comparisons as right-aligned `uint64` values across
  calldata, memory, cursor, and execution helpers. Fixed-layout checks share
  named `Headers` constants derived from `Specs`, exported through `Codec.sol`
  and `Commands.sol`. Readers that need individual fields extract the key and
  length directly in assembly: both `header` overloads, the direct `enter`
  overloads, `runCount`, and LIST/BYTES/STRING unpackers.

## 1.38.0

### Breaking Changes

- Remove `Executions.enterNext`; use `while (exec.more())` followed by
  `exec.enter(spec)`. `BookPort` now uses the separate traversal and entry helpers.
- Rename annotation contracts to `ActionAnnot`, `CounterpartyAnnot`, `LabelAnnot`,
  and `SchemaAnnot`, keeping their existing file paths. Rename the action and
  counterparty helpers to `annotateAction` and `annotateCounterparty`; `label`
  and `schema` retain their names.
- Remove `PostPort.portPost`; use `BookPort.portBook` for transfers and
  single-sided entries, explicitly setting omitted legs to zero amounts.
  Keep the `Tx` struct and transaction encoding/decoding helpers.
- Rename `ExchangePort.portExchange` to `BookPort.portBook` and move its import
  to `ports/Book.sol`. The selector changes; callers must use the new endpoint.
  The input schema is unchanged. Hook routing, zero-amount handling, and decode
  ordering change as described below.
- Generalize `BookHook` to `book(from, to, asset, amount, liability, debt)` and
  remove `PostHook` and the internal `post` helper. Book commands, book ports,
  and settlement transfers use this shared hook directly.
  `Settlement.book` preserves debit-first funding and skips zero amounts.
  The book port now decodes both legs before invoking the hook and skips zero-amount
  account operations, which can change error precedence and hook observations.
- Change all port return types and the existing `rawCall` / `rawCallCopy` helpers
  to `(bytes, uint credit)`. Callers must decode the tuple and handle trusted
  credit; this return-type change preserves selectors, so old bytes-only callers
  are incompatible even without a selector change.
  Dispatch ports return unspent budget. `PipePayablePort` preserves its final
  `cashin` to the last context's account and returns zero credit. `Portal.forward`
  continues to ignore successful return data. Query results remain bytes-only.
- Remove the default `Settlement.settle` implementation, leaving its inherited
  `SettleHook` abstract. Hosts implement their own settlement hook and fee policy using
  the internal `repay` and `collect` helpers. Existing overrides should no longer
  name `Settlement` as a settle implementation.
- Add unindexed `counterparty` after `debt` and before `action` in `Positioned`.
  Update emitters and indexers for the new event signature.
- Move `PositionedEvent` from `events/Positioned.sol` to `events/Position.sol`,
  alongside `SettledEvent`. Imports through `Events.sol` remain unchanged.

### Added

- Add `ActionEvent` with `Action(bytes32 indexed account, uint32 action)` and
  deployment-time ABI discovery, exported through `Events.sol`.
- Separate regular tests from benchmarks: `npm test` excludes `*.bench.test.ts`,
  `npm run bench` runs them explicitly, and `npm run test:all` runs the full suite.
  Explicit test-file selection remains supported.
- Document the intended realize/settle host models, add host-payer settlement
  coverage, and benchmark the four fee paths with empty and existing recipient
  balances. Results and reproduction instructions are in `docs/SettlementGas.md`.
- Add shared `ZeroFee` in `utils/Errors.sol`, exported through `Utils.sol`, for
  required fees that cannot be collected within the limits.
- Add reusable `HostAccount` in `core/Runtime.sol`, exported through `Core.sol`.
  `Settlement` inherits its immutable host account identity.
- Add internal settlement helpers without fixed fee rates. Fees go to the immutable
  `hostAccount`, derived from the settlement contract address. The
  `repay` helper tries a liability surcharge; `collect` falls back to an asset-side
  deduction. `repay` returns the input basis points until a nonzero fee is
  collected, then zero. `collect` reverts with `ZeroFee` if it cannot
  collect a pending fee and has no return value.
  Each helper enforces its own base amount limit before transfers; zero debt
  returns immediately since it cannot exceed an unsigned maximum.
  When the counterparty is the fee recipient, repayment combines its credits and
  collection debits only the net asset amount, omitting a separate fee credit.
- Add `Fees.deductible` and `Fees.addable` through `Utils.sol`. They return
  rounded-up basis-point fees only when the full fee fits the inclusive limit,
  otherwise zero, with overflow-safe calculation.
- Add `Fees.calculate` with signed `int16` basis points: positive adds, negative
  deducts, and the returned fee quantity is unsigned.
- Add `SettledEvent`, exported from `Events.sol`, for fully settled positions
  with only `account` indexed.

## 1.37.0

### Breaking Changes

- Remove stride/group metadata from block specs, endpoint descriptors, execution
  sources, and cursors. Each top-level block now represents one operation;
  fixed compositions use a custom parent block. Re-encode packed metadata and
  update offchain descriptor/cursor readers to the layouts in `docs/Schema.md`.
- Remove `Specs.stride`, `normalize`, `lane`, `count`, `groupSize`, and `group`,
  and remove `Cursors.meta`. Use `Specs.blockSize`, block-count allocation,
  `Cursors.create(pos, end, flags)`, and `Buffers.cursor(capacity)`; cursor flags
  move to bits 64-71.
- `Realize` consumes one LIMITS input per POSITION instead of QUOTE and calls
  `realize(account, position)`. The command enforces returned quantity limits;
  the hook must preserve asset/liability identifiers, authorize and fulfill the
  counterparty obligation, and return counterparty zero.
- `Settle`, `SettlePayable`, and `ExecuteSettle` require one LIMITS input per
  POSITION. Settlement hooks now accept `Limits memory limits`, before the
  execution budget argument for payable settlement, and must enforce inclusive
  minimum net amount and maximum total debt, including fees.
- Default `Settlement.settle` now requires an account-category counterparty and
  rejects zero. Use `Book`/`ExecuteBook` for Rootzero-backed positions with zero
  counterparty. Self-settlement remains supported.

### Added

- Add LIMITS (`uint amount, uint debt`), its structured `Limits` type, scalar and
  structured codecs, and calldata `requireLimits` helpers. QUOTE codecs and
  `Positions.requireQuoted` remain available independently.
- Add `Book`, `ExecuteBook`, and `BookHook`, with the `Actions.Book` annotation.
  Default booking debits the exact liability then credits the exact asset amount,
  skips zero quantities, and reverts atomically on failure.
- Add `ExchangePort.portExchange` for trusted peers. Each local-key-1 parent has
  an exact 208-byte payload containing debit and credit ACCOUNT_AMOUNT children.
  Empty batches are accepted; invalid parents, children, or hooks revert the batch.
- Add schema-reference shorthand `#schema as (first, second)` for unmodified
  references with distinct aliases. It preserves child keys and wire layout.
- Add `Executions.enterNext`, combining both-source traversal checks with input
  parent entry through shared `Blocks.enter`; use it in ExchangePort.
- Add explicit gas-limit overloads of `tryRawCall` and `tryRawCallCopy`, grouping
  `value, gasLimit` before `input` and retaining the existing overloads.

### Fixed

- Reserve recovery gas in `Portal.forward` for copying, hashing, memory expansion,
  call/value overhead, and unresolved-message storage after pipe out-of-gas.
  When no pipe budget remains, attempt digest storage directly. Recording can
  still revert if even that work cannot be funded. The fixed immutable reserve
  defaults to 35,000 and can be increased by derived constructors.
- Make `rawCall` and `rawCallCopy` reject every nonempty output when `expectEmpty`
  is set, including even lengths previously accepted by the bitwise check.

### Performance and Verification

- Reuse validated lengths and reserved buffer sizes in block factories, Writers,
  and execution output helpers. Avoid full zero initialization when factories
  overwrite their payload, while retaining allocation size and clean padding.
- Reduce repeated bounds arithmetic, fixed-header checks, and cursor work in
  Blocks, Decoders, Executions, Buffers, and Cursors. Centralize spec validation
  in `Blocks.enter`; retain the normal entry wrappers to limit deployed size.
- Precompute endpoint lane-presence bits, streamline raw source access and
  BALANCE-stream consumption, and remove proven-redundant budget subtraction checks.
- Remove the extra successful-returndata wrapper from raw call/query helpers,
  saving one allocated memory word per successful call.
- Add frozen-baseline differential tests, gas and deployed-size measurements,
  malformed-input and overflow cases, dirty-memory and allocation checks, and
  forwarding/recovery, LIMITS, booking, and exchange regressions.

## 1.36.0

- Add `Accounts.account(value)` to validate only the account category and return
  the ID unchanged, reverting with `InvalidAccount` for non-account values,
  including zero.

- `PipePayablePort` now requires `CashinHook` and credits any remaining shared
  budget to the last context's account after all pipelines complete. Empty input
  with native value passes the zero account to `cashin`; account validation is
  the hook's responsibility.

- Add the abstract `CashinHook` for crediting native value already held by a host
  to an account. Group it with `CashoutHook` in `core/Cash.sol` and export both
  through `Core.sol` and `Endpoints.sol`.

- Add an exact counterparty requirement to QUOTE (160-byte payload), share the Position struct for decoded quotes, and reject mismatched returned counterparties during realization.

- Repack endpoint descriptors into uniform key/stride lanes with a dedicated source key/stride lane, a direct decoder shift, and precomputed source and output group sizes. Prefer declared state over input for allocation. Estimate output capacity by divisible source length, falling back to run counting; default source-free output capacity to one group; remove unused output bounds from discovery descriptors.

### Breaking Changes

- Move `Budget` and `Budgets` from `execution/Budget.sol` to `core/Budget.sol`.
  The `Core.sol` exports are unchanged.

- Move embedded EVM account and ERC-20 addresses from bits `[191:32]` to
  `[159:0]`, matching node IDs. Their encoders now leave bits `[191:160]` zero.
  Existing account and ERC-20 IDs must be re-encoded, including persisted keys
  and offchain inputs; old IDs are not automatically migrated. Node IDs and
  opaque IDs keep their existing layouts.

- Removed the remaining `RepayPosition`/`RepayPositionPayable` commands and
  `RepayHook`/`RepayPayableHook`. Use `settle`/`settlePayable` with liability-only
  positions to repay. Default settlement debits the liability directly; full
  positions settle both sides and no longer have a repay-to-BALANCE command.

- Renamed the `Clearinghouse` annotation mixin/helper to `Counterparty` and its
  block from `#clearinghouse` to `#counterparty`. The payload is now `bytes32 account`,
  including host accounts; zero identifies Rootzero. Updated the schema, spec, factory, and public export.

- Settlement hooks now take `(bytes32 account, Position memory position)`, plus
  `Execution memory funds` for funded settlement. `settle`, `settlePayable`, and
  `ExecuteSettle` forward the complete struct without checking its counterparty.
  Counterparty validation and authorization
  belong to the hook; the default `Settlement` implementation accepts Rootzero
  or an account category via `Accounts.counterparty`. It transfers liability to
  the counterparty and the asset in the opposite direction, skipping counterparty
  operations for Rootzero.

- Moved `UnexpectedValue()` from `Blocks` to shared `utils/Errors.sol` and
  exported it through `Utils.sol`. Import the shared error instead of using
  `Blocks.UnexpectedValue`; its revert selector is unchanged.

- Removed `Assets.toDerived`, `isDerived`, `derived`, and `matchDerived`.
  `Layout.Derived = 0x01` remains reserved without dedicated helpers or a
  standardized subtype-specific payload.

- Consolidated realization into `Realize`/`realize`: it consumes and returns
  POSITION state, with one QUOTE input (asset/minimum, liability/maximum, and exact counterparty).
  Removed `RealizePosition`/`realizePosition` and the former balance-only behavior.

- Removed the DEBT schema, its codec APIs and `Debt` value type, and the
  `RealizeDebt`, `Repay`, `RepayPayable`, and `ExecuteRepay` commands/adapters.
  Debt is a POSITION with zero asset and amount; use position commands instead.
- Added `bytes32 counterparty` as the fifth POSITION field, increasing its payload
  from 128 to 160 bytes. The default settlement hook accepts Rootzero
  (`0`) or an account counterparty and rejects other categories with `InvalidAccount()`.
  Realization delegates counterparty validation to its hook. Generic codecs
  preserve all five fields. Old POSITION encodings must migrate.

- Replaced the primitive realization hooks with `realize(Position, Position quote) -> Position`.
  The hook validates and fulfills the counterparty obligation and chooses its
  internal operation order. The command decodes the paired QUOTE before calling
  the hook and emits its complete result. The hook must enforce the quote;
  `Positions.requireQuoted(position, quote)` provides shared decoded checks.
  Removed the unused encoded-validation helpers `Blocks.requireQuoted`,
  `Decoders.requireQuoted`, and `Executions.requireQuoted`.

- Renamed `BadAmount(uint amount)` to `AmountOutOfRange()`, removing the argument
  and updating the amount validation helpers and public export.

- Unified stored balances in `Balances`, keyed by `(account, asset)`. Removed
  `AccountBalances` and the separate host ledger; hosts use `Accounts.toHost(host)`.
  The mapping is now `balances[account][asset]`, with `creditTo`/`debitFrom` helpers.
  This changes the storage layout of the former host ledger.
- Removed `CreditHostHook`/`DebitHostHook` and `CreditPort`/`DebitPort`.
  Use `portCreditAccount`/`portDebitAccount` and account hooks for host accounts too.
- Consolidated balance queries into `GetBalances`/`GetBalancesHook`, with
  the account-based `getBalance(account, asset)` hook and `getBalances`
  endpoint. Supply the host account to query host holdings.
- Unified balance events as `Balance(bytes32 indexed account, bytes32 asset,
  uint balance, int change)` from `BalanceEvent`. Removed `AccountBalanceEvent`;
  there is no separate host-indexed event or access field.

### Features

- Refactored pipeline command invocation into named Yul helpers for call encoding,
  failure wrapping, and result decoding. Preserved scratch-memory reuse, canonical
  ordinary/handoff encoding, and strict return-shape validation.

- Added deterministic host accounts using the shared `Layout.Host` subtype under
  `Layout.Account`, with `Accounts.Host`, `isHost`, `host`, and `toHost` overloads
  for addresses and host node IDs. Node conversion preserves the source chain.

- Added `Memory.unpackPositionValue` for decoding a complete position struct;
  `ExecuteSettle` uses it to forward all fields to the settlement hook.

- Added `Accounts.isAccount` to classify the account category byte and
  `Accounts.counterparty` to accept Rootzero (`0`) or that category unchanged,
  reverting with `InvalidAccount()` otherwise. These helpers do not validate
  representation, subtype, payload, or authorization.

- Added the five-field QUOTE input schema sharing the `Position` value type, with block,
  cursor, execution, and writer helpers. Asset amount is a minimum and liability
  debt is a maximum; counterparty must match exactly. `Positions.requireQuoted`
  checks matching identifiers and inclusive limits against a decoded quote,
  using `UnexpectedValue()` and `AmountOutOfRange()`.

- POSITION counterparties are Rootzero (`0`) or account IDs, including host
  accounts. Realization hooks match the executing host account instead of its
  node ID. Host accounts also support ordinary settlement where funded; routing
  is independent of account subtype. Both commands delegate validation to hooks.

## 1.35.0

### Breaking Changes

- `RelayBalancePayable` now validates the entire forwarded state with
  `takeRawBalances()`, rejecting non-BALANCE and malformed blocks. Empty state
  remains supported.

- Assigned explicit representation bytes `Rootzero = 0x01`, `Opaque = 0x02`,
  and `Evm = 0x03`, reserving `0x00` for null/unset IDs. All structured EVM
  IDs and opaque hash-backed IDs now encode with their new representation byte.

- Changed opaque IDs from `[0x00][bytes31(hash)]` to
  `[0x02][category][subtype][bytes29(hash)]`. Keccak preimages now use
  `[0x01][category][subtype][payload...]`, cryptographically binding the visible
  category and subtype to the opaque identity. Category-specific helpers reject
  opaque IDs and preimages from other categories.

- Added asset subtypes `Derived = 0x01` and `Virtual = 0x02`, and moved `Erc20`
  from `0x02` to `0x03`. `Assets.toDerived(asset, host)` now creates a
  deterministic opaque asset scoped to a host, with inspection, assertion, and
  matching helpers. `Virtual` is reserved as a taxonomy value without helpers.

- Renamed the chain coin/token identity from `NativeAsset`/`nativeAsset` to
  `ChainAsset`/`chainAsset`. The asset helpers are now `Assets.toChain`,
  `Assets.isChain`, and `Assets.chain`. The chain asset is now the
  subtype-zero default EVM asset; its representation byte changes as described
  above.

- Changed `DepositHook` and `DepositPayableHook` to return the actual amount
  received by the hook. Deposit execution now encodes that returned amount as
  balance state, allowing external ingress fees or other differences from the
  requested amount without overstating live value.

- Renamed the account-scoped balance query from `GetBalances`/`getBalances` to
  `GetAccountBalances`/`getAccountBalances`, changing its query ID accordingly.

- Renamed the two-key `Balances` account ledger to `AccountBalances` and its
  internal mapping to `accountBalances`.

### Features

- Added `GetBalances`/`getBalances`, a host-scoped holdings query that maps
  `#asset` inputs to non-state `#amount` responses.

- Added a host-scoped `Balances` ledger keyed directly by asset, with
  `credit(asset, amount)` and exact-or-revert `debit(asset, amount)` mutations.

- Added host-scoped `CreditPort`/`portCredit` and `DebitPort`/`portDebit`
  endpoints. Both consume `#amount` blocks, complementing the account-scoped
  ports that consume `#accountAmount`. Their `creditHost` and `debitHost` hooks
  are separate from the `Balances.credit` and `Balances.debit` storage helpers.

- Added the account-independent realization command family, all publishing
  `Actions.Realize` (`17`). `realize` maps paired `#balance` and `#amount`
  blocks to hook-adjusted `#balance` state, while `realizeDebt` does the same
  for `#debt`. `realizePosition` pairs `#position` state with two `#amount`
  inputs, realizes its two sides through the balance and debt hooks, and emits
  their combined `Position`. Also added the reusable
  `#assetLiability { bytes32 asset, bytes32 liability }` block.
  Realization hooks take their source first, requested destination second, and
  `uint limit` last. AMOUNT inputs carry the destination and minimum output
  balance or maximum replacement debt. Hooks enforce limits; command loops
  forward them and use the returned quantities. Position realization declares
  input stride two and consumes asset/minimum first, then liability/maximum.

- Added the singleton global Rootzero asset ID `[Rootzero][Asset][0][0]`, with
  zero chain and payload fields. Its canonical value is available directly as
  `Assets.Rootzero`, with inspection and validation helpers in `Assets`.

- Added the standard `#clearinghouse { uint host }` annotation and
  `Clearinghouse` helper for associating an entity with its clearing host. The
  latest trusted value replaces the prior association, and host zero clears it.

### Fixes

- Documented trusted peers as fully validated extensions of the receiving host,
  authorized across its entire port surface. Clarified admission requirements,
  the single entrypoint peer check, and the absence of per-operation peer
  permissions; retained the distinction between authorization and validity checks.

- Defined debt realization to transform the entire source obligation
  into its complete replacement or revert. Added realization tests for unequal
  batches, mixed and malformed trailing blocks, and atomic rollback of hook
  mutations, including asset mutations preceding a position's debt-hook failure.

- `Pipeline.invokeCommand` now clears outgoing ABI padding even when temporary
  memory contains old data, and retains only the returned buffer so later steps
  can reuse memory occupied by large command inputs. Added ordinary and handoff
  encoding boundary tests, state growth/shrinkage coverage, and a memory/gas
  benchmark; documented the packed cursor's handoff discriminator.

## 1.34.0

### Breaking Changes

- Centralized commander identity and default access storage in `Runtime` and
  `Host`. Removed `CommanderAccess`, the `Admins` and `Guardians` feature
  bundles, and the distinct `CommanderNotAllowed` error; peer rejection now
  uses `AccessDenied`. `CommandHost` remains the minimal commander-only base,
  while access capability contracts are abstract hook surfaces.
- Simplified generic `Cursors` to one source. Removed paired-cursor lanes,
  selection and swapping, cursor identity tags, `Lanes`, and `MissingCursor`.
  `Buffers.cursor` no longer accepts a tag and `Cursors.meta` now returns only
  stride and consumer flags. Generic cursors now pack only absolute current/end
  positions plus metadata; buffer positions use origin zero. Removed the stored
  offset/relative length model and its `decode`, `frame`, `initial`, `seekAbs`,
  and `expectAbs` helpers. Low-level `Cursors` and `Decoders` navigation,
  slicing, inspection, and returned positions are now consistently absolute.
- Specialized `Execution.decoders` as one packed word with fixed absolute input
  and state positions. Input helpers always consume input; `unpackBalance`,
  `unpackDebt`, `unpackCustody`, and `unpackPosition` always consume state, so
  `oninput` and `onstate` were removed.
- Defined Balance, Debt, Custody, and Position as the closed typed state-block
  set and grouped them consistently in Keys, Sizes, Specs, Schemas, and test
  encoding helpers. Custom and dynamic schemas remain input-only.
- Moved endpoint description and execution cursor opening from `Descriptors`
  into `Executions`. Use `Executions.describe` and initialize cursors through
  `exec.open` or `exec.openInput`; raw specialized cursor tuples are no longer
  exposed. `exec.open` now initializes the command account and explicit budget
  together with state, input, and output, while `exec.openInput` initializes an
  explicit budget with its input and output.
- Removed the `Redeem` port surface.
- Simplified `Blocks.exact` to return only the absolute payload position. Its
  validated end is always the supplied calldata slice's end; callers needing
  explicit bounds can use `Blocks.enter`.
- Added an `expectEmpty` argument to `rawCall` and `rawCallCopy`. When enabled,
  a successful call reverts unless its decoded `bytes` result is empty. Try-call
  helpers remain output-agnostic so failed forwards can still be recorded for
  recovery.

## 1.33.0

### Added

- Added `addValue` to standalone `Budget` and `Execution` values so trusted
  hooks can contribute backed native value to the current budget in place.
- Added selector/address `tryRawCall` and `rawCall` helper families. They encode
  supplied memory or calldata as a function's single `bytes` argument; non-try
  helpers expose the returned `bytes` directly. Calldata variants use a `Copy`
  suffix and avoid intermediate ABI allocation.
- Added `ForwardHook` as the transport-facing portal forwarding capability.
- Added the canonical `PortPipePayableSelector` beside `PipePayablePort` and
  exported it through the endpoint barrel.
- Added `Nodes.decode` for resolving any local node ID into its ABI selector
  and embedded address, including zero-valued fields.

### Changed

- Replaced generic outbound `TrustAccess` validation with narrow
  `CommandAccess.enforceCommand` and `PortAccess.enforcePort` capabilities.
  `NodeAccess` implements both by validating the endpoint type and its trusted
  node entry together and returning its selector and address, while retaining
  `enforceTrusted` as its concrete generic trusted endpoint resolver.
- Decoupled `GuardianAccess` from `NodeAccess`; only the `Revoke` guard now
  requires node access explicitly, reducing inheritance requirements for other
  guardian actions.
- Specialized `ExecutePayable` with a private arbitrary-call path that ignores
  successful returndata and copies returndata only when reporting failure.
- Added one memory-based `rawQuery` helper for infrequent dynamic protocol
  queries. It encodes a single `bytes` argument and exposes the returned bytes
  directly.
- Specialized `Portal` ordinary delivery to forward CONTEXT streams directly
  to its commander's `portPipePayable` endpoint. Recovery continues to accept a
  separately selected trusted handler port for transport-specific failures.
  Failed delivery now records its digest and emits `Unresolved` atomically.
- Narrowed `Portal.resolve` to validate and delete an unresolved witness. The
  recovery implementation now chooses and invokes its handler, so `Portal` no
  longer depends on `PortCalls` or the broader `NodeAccess` capability.

### Breaking Changes

- Removed the `NodeCalls` and `PortCalls` inheritance helpers. Callers now
  authorize commands or ports through the access layer and invoke the free raw
  call helpers directly.
- Removed the unused complete-calldata encoded call and query helper family.
- Selector/address raw helpers now treat supplied bytes as the raw contents of
  one `bytes` argument.
- Removed the destination port argument from `Portal.forward`; portal
  implementations now use `forward(bytes32 key, bytes calldata message, uint
  value)` and ordinary delivery always targets the commander pipeline.
- Changed `Portal.resolve` from `(uint handler, bytes32 key, bytes calldata
  witness, uint value)` to `(bytes32 key, bytes calldata witness)`; recovery
  implementations are responsible for their own handler calls and trust policy.

## 1.32.0

### Added

- Added `Blocks.enter` overloads for validating either a block specification or
  only its key and returning absolute payload bounds from a calldata slice or
  absolute position. The slice overload also returns its absolute limit. These
  low-level helpers deliberately leave region-length validation to the caller.
- Added spec and key `Blocks.enter` prefix overloads returning `(body, next,
  end)`. Decoder and execution prefix entry now delegate prefix validation and
  next-position calculation to these low-level helpers, and both layers expose
  matching key-based entry overloads.
- Added `Specs.matches` to validate a block key and payload length against a
  specification in one operation.
- Added `Blocks.exact` to validate that a calldata slice consists of exactly one
  block matching a specification.

### Changed

- Renamed the key-only `Blocks.expectKey` helper to the `Blocks.enter` overload.

### Breaking Changes

- Removed the unused standard `#evm` block and its dedicated key, spec, schema,
  block, writer, execution, and test helper APIs. Opaque payloads use `#bytes`.
- Qualified byte-content schemas now identify ordinary encoded block streams
  inside aliased `#bytes` fields. Each contained top-level block carries the
  selected schema's key and obeys its payload bounds, allowing implementations
  to use `Blocks.exact` for a single block or the standard decoder and
  close-validation helpers for batches. This replaces the v1.31.0 convention
  that treated qualified contents as headerless fields.

## 1.31.0

### Added

- Defined qualified byte-content schemas such as `relay.input`. A dotted
  schema annotation name binds its schema body directly to the raw contents of
  the aliased `#bytes` field at that structural path without changing the wire
  format. Locally emitted schemas take precedence over trusted-context and
  standard schemas with the same name.
- Clarified that built-in block names are part of the protocol's standard
  schema catalog. Indexers resolve a standard key to its canonical name even
  when no schema annotation is emitted or its `name` field is zero.

### Breaking Changes

- Relay hooks now receive the command `account`, command-specific `input`, a
  fully constructed canonical destination `context`, and `funds`. Relay commands
  also place the account, complete forwarded state, and remaining STEP stream
  into that context before calling the transport hook.
- Decoupled inbound port endpoints from the full `NodeAccess` and outbound
  `NodeCalls` inheritance trees. `PortBase` now depends only on the narrow
  `PeerAccess` capability implemented by `NodeAccess`, reducing shared-base
  constraints when composing port and command bundles. Custom port hosts must
  now provide `PeerAccess`, and custom ports that make outbound calls must
  inherit or import that functionality explicitly.

## 1.30.0

### Breaking Changes

- Replaced the obsolete second representation/width byte in every structured
  ID with a trailing flags byte. The type prefix is now
  `[uint8 representation][uint8 category][uint8 subtype][uint8 flags]`, changing
  every structured account, asset, and node ID. Endpoint IDs copy the same flags
  published in their descriptors.
- Added the canonical handoff command flag. Relay commands now publish command
  IDs carrying `Flags.Handoff`. `Pipeline.pipe` now wraps a flagged STEP's
  ordinary input and untouched continuation in a RELAY block, calls the handoff
  command once, and stops local execution of that continuation.
  The internal RELAY block changed from `(portal, resources, input)` to two
  nested byte streams: command-specific `input` and remaining `steps`. Relay
  hooks now receive `account`, complete `state`, opaque command input, remaining
  steps, and their value budget; each transport implementation decodes its own
  command input.
- Added `Flags.HandoffFunded` as the canonical combination used by funded
  handoff commands, matching the existing `Flags.AdminFunded` convention.
- Removed the free `rawCommandCall` API and moved its cursor-aware assembly path
  into `Pipeline` as a private implementation detail. Pipeline's private `run`
  path now owns local execution, trust, command unpacking, handoff selection,
  invocation, and cursor advancement. `pipe` accepts the STEP stream as
  calldata and packs its current position, end, command-input offset, and
  command-input length into one private cursor. The invocation path uses those
  fields directly for ordinary input or to wrap a handoff continuation in a
  RELAY block.
- Removed the free `unpackCommand` utility. Pipeline now privately validates
  command IDs and extracts the target and direct handoff decision needed for
  routing; the private invoker derives selector and target directly from the ID.
- Aligned no-argument `raw` access across cursors, decoders, and executions to
  return only the unread region from the current position. `rawState`,
  `rawInput`, `takeRawState`, and `takeRawInput` now follow the same rule;
  explicitly bounded `raw(from, to)` slices remain frame-relative.

- Replaced the stateless `RawNodeCalls` inheritance contract with imported
  `tryRawCall`, `rawCall`, and `rawQuery` free functions. Added overloads that
  accept a selector and native target separately from selector-free ABI
  arguments, without allocating a concatenated calldata buffer.
- Changed `Host`, `CommandHost`, `CommanderAccess`, and `HostIntroduction`
  constructors from an EVM `address` to a protocol-native `uint` commander host
  ID. Nonzero commanders must be valid local host IDs; the EVM address is
  extracted internally for caller checks and introductions, while zero retains
  the self-commanded `Host` convention and remains invalid for `CommandHost`.
- Removed `RequestAllowanceHook`. `RequestAllowancePort` now reuses the
  authoritative `AllowanceHook` and scopes each allowance update to the
  authenticated peer before calling `allowance(peer, asset, amount)`.
- Changed `Cashout` from a `#cashout { uint amount }` input command into a
  native-only `#balance` state consumer. Removed the CASHOUT block key, spec,
  schema, codec helpers, and test encoder; cashout now reverts `InvalidAsset`
  for non-native balance state.
- Reordered `Settlement` hook inheritance to `PostHook`,
  `DebitAccountHook`, `CreditAccountHook`, `SettleHook`, and `RepayHook`.
  Downstream hosts combining `Settlement` with hook-bearing endpoints may need
  to reorder their base contracts.

### Changed

- Reduced per-step pipeline overhead by replacing the general lane cursor with
  a private four-field pipeline cursor, specializing STEP advancement around
  decoder-established bounds, preparing handoff input once, and avoiding
  command and flag work on paths that do not need it.

## 1.29.0

### Breaking Changes

- `ExecuteHook.execute` and the optimized local command helpers now return a
  leading `bool handled`. A local command returned as unhandled is invoked
  through its trusted normal external command entrypoint; handled commands keep
  the optimized internal path and are authorized by the hook implementation.
- Renamed `CashoutInternal`, `DebitAccountInternal`, `CreditAccountInternal`,
  `SettleInternal`, and `RepayInternal` to `ExecuteCashout`,
  `ExecuteDebitAccount`, `ExecuteCreditAccount`, `ExecuteSettle`, and
  `ExecuteRepay`.

## 1.28.0

### Breaking Changes

- Expanded STEP's native `value` field from `uint128` to `uint`, increasing an
  empty STEP block from 64 to 80 bytes. Plain native values now use `uint`
  throughout runtime APIs; packed `resources` remain separate `uint` words
  whose EVM value lane is extracted explicitly with `useResourceValue`.
- Replaced the `CommandCalls` abstraction and its allocating `encodeCommandCall`
  and `callCommand` helpers with the free `rawCommandCall` function. The caller
  now supplies the decoded selector and target after validating and authorizing
  the command, then uses the single-scratch assembly call path.
- Added the required `ExecuteHook` to `Pipeline` and removed its `dispatch` hook.
  Steps whose command IDs target the current host use `execute`; other commands
  are checked through `TrustAccess` and called directly with `rawCommandCall`.

### Changed

- Added the free `unpackCommand` utility for validating a command node and
  extracting its selector and target in one operation. Pipeline steps now use
  it to validate command IDs and select local execution by target address.
- Simplified `NodeAccess.ensureTrusted` to a single mapping check; an unset zero
  node already resolves to false like every other untrusted node.

## 1.27.0

### Breaking Changes

- Removed `BootstrapBudgetHook`. Bootstrap budget contributions now debit the
  account's local native asset through the standard `DebitAccountHook`.
- Removed the external `bootstrap` endpoint and `BootstrapInternal`. Bootstrap
  is now a pipeline-local command implemented directly by `Bootstrap` while
  retaining its registered command ID and descriptor metadata.
- Replaced the codec-specific `Executions.ZeroStride` error with global
  `UnexpectedState` and `UnexpectedInput` errors for pipeline-local lane
  violations.

### Changed

- Node authorization and revocation now reject foreign-chain and opaque node
  IDs, keeping the trusted-node set local to the host chain.
- Asserting EVM, admin, and user account helpers now require a nonzero embedded
  address while continuing to return the original account ID.
- Documented that either side of a position may be absent, using a zero
  identifier and quantity like an omitted transaction endpoint.
- Bootstrap uses assigned step value before debiting any remaining native-asset
  amount from the account and returns unused value as credit.

## 1.26.0

### Breaking Changes

- STEP blocks now encode `uint128 value` directly instead of a full-width
  chain-specific `uint resources` word. The fixed STEP prefix is 16 bytes
  smaller, and pipeline dispatch no longer truncates or interprets resource bits.
- Commands now return `(bytes state, uint credit)` instead of separate state
  and transaction block streams. Pipelines trust the scalar return and add it
  to the shared value budget, allowing later commands to spend it before the
  enclosing entrypoint settles the final budget once. Transaction blocks remain
  available for explicit posting through ports.
- Removed transaction writer metadata from endpoint descriptors and execution
  writer lanes.
- Removed descriptor checks, eager lane scans, group reconciliation, and the
  expected batch argument from execution opening. State/input keys and strides
  remain descriptor metadata; command decoding and loops define their runtime
  semantics, while finalization rejects unread state or input bytes.
- Removed the generic memory-backed `Reader` and `Readers` API from
  `Codec.sol`. Fixed homogeneous memory streams now use absolute-position
  `Memory` unpackers.
- Removed `Decoders.wrap` and the scanning `Decoders.batch` constructor.
  `Decoders.open` now wraps any calldata source without initial checks,
  including empty sources; explicit decoding defines structure and cardinality.
- Removed the unused `Cursors.pair`, `locate`, and `before` helpers. Cursor
  pairs are packed directly where execution needs them.
- Replaced the cross-chain-ambiguous `#budget` block with the command-specific
  `#cashout { uint amount }` block.

### Added

- Added the standard
  `#bootstrap { bytes32 asset, uint amount, uint budget }` input block and
  `Bootstrap` command. It uses the standard `DebitAccountHook` for each initial
  balance and a dedicated `BootstrapBudgetHook` for native-value contributions,
  including zero contributions. `BootstrapInternal` provides direct local
  pipeline dispatch without a self-call.
- Added `Cashout`, its dedicated native-withdrawal hook, optimized
  `CashoutInternal` dispatch, and the canonical `Actions.Cashout` annotation.
  Added `Actions.Cashin` as its native-deposit counterpart.
- Added `utils/Errors.sol` as the canonical declaration source for all
  utility-layer errors, preserving their existing signatures and selectors.
- Added hint-only `Blocks.runCount`, a minimal assembly scan that counts complete
  consecutive keyed blocks without treating the result as structural validation.
- Added `Executions.takeRawState` for forwarding an intact state lane while
  marking it consumed.
- Added symmetric `Executions.takeRawInput` for forwarding and consuming an
  intact input lane.
- Added `Decoders.close` to reject unread bytes explicitly. Execution `finish`
  and `close` apply the same invariant automatically.
- Added `Execution.close(extraCredit)` to combine trusted command-produced
  credit with the execution's remaining value budget during finalization.
- Added `Memory.bounds` and specialized `unpackBalance`, `unpackDebt`,
  `unpackPosition`, and `unpackTransaction` helpers for fixed-stride memory
  block streams.

### Changed

- Replaced the unused checked `Cursors.wrap(source, flags, tag)` with the
  two-argument packed calldata wrapper used by generic decoders. Removed the
  duplicate private execution `openDecoder` implementation.
- Replaced the unused cursor item-count metadata with an optional one-byte
  block stride. `Descriptors` now fully opens single or paired decoder cursors,
  selects the active lane, derives the output allocation hint, and initializes
  the writer cursor. Removed descriptor field accessors so packed layout
  interpretation remains internal to the codec. Endpoint and command helpers
  now construct `Execution` directly with the returned cursors and `msg.value`;
  removed the descriptor-backed `Executions.open*` wrappers.
- Execution output writers now derive their initial capacity from an optimized
  hint-only scan of the selected low decoder lane and grow as needed. Output
  strides and size hints no longer impose a hard precomputed batch capacity.
- All buffers now grow beyond their initial capacity. Removed the `Growable`
  cursor flag and the growth-policy booleans from buffer, writer, specification,
  and descriptor allocation APIs.
- `Execution` now stores its sole output writer as a direct untagged cursor;
  output reservation and finalization no longer perform lane selection.
- Execution traversal and unpack helpers now consume the active low decoder
  lane without a lane argument. Mixed-lane commands select explicitly with
  chainable `onstate()` and `oninput()` helpers. Paired executions use descriptor
  metadata to place state low for state-only commands, which decode directly.
  Relay commands select input explicitly before decoding their forwarded block.
- `Execution.close()` now finalizes output and drains the remaining budget as
  `(bytes output, uint credit)`; commands return it directly without the former
  `CommandBase.closeCommand` wrapper. Budget draining is inlined in `close()`.
- Internal debit processing now validates its fixed calldata stride once and
  decodes each amount directly. Internal credit, settlement, repayment, and
  pipeline transaction processing do the equivalent for memory streams.
- Pipeline step value is now checked and deducted directly from the scalar
  budget, avoiding the generic budget-helper call in the dispatch loop. The
  loop now also traverses absolute calldata bounds and unpacks STEP blocks
  directly without allocating a decoder cursor.
- `Cursors` now performs packed construction, bounds, navigation, selection,
  and consumption directly in each helper, avoiding nested internal-call
  overhead across low-level decoding paths.
- `Blocks.expectKey` and the specialized dynamic leaf unpackers now validate
  their headers directly, reducing composite decoding overhead.
- `Specs` and `Descriptors` now calculate hot-path counts and writer allocation
  directly from their packed fields.
- Buffer reservation/finalization, fixed-size writer reservation, and execution
  opening/output paths now operate directly on validated packed cursors.

## 1.25.0

### Breaking Changes

- Changed `Pipeline.pipe` to accept a scalar `uint` budget and return the
  remaining scalar budget. The standalone mutable `Budget` type remains
  available for other funded execution flows.
- Split the pipeline hook from its standard implementation. `PipePayablePort`
  now inherits only `PipeHook`; hosts that want the built-in pipeline must
  compose `Pipeline` explicitly, while custom hosts may implement the hook
  without inheriting the standard dispatch and posting implementation.
- Changed `Decoders.open` to wrap the complete non-empty calldata source as an
  ungrouped cursor. Code that needs the former counted first-homogeneous-run
  behavior must use the new `Decoders.batch` helper.

### Added

- Added scalar `Budgets.useValue` and `Budgets.useResourceValue` overloads, and
  `Executions.drainBudget` for transferring an execution budget as a `uint`.
- Added `PipeHook` to the `Core.sol` and `Endpoints.sol` package barrels.
- Added `Blocks.expectKey` and key-only `Decoders.consume` and
  `Executions.consume` overloads for validating blocks whose payload shape is
  established by specialized decoding logic.
- Added `Blocks.require1`, `require2`, `require4`, `require8`, and `require16`,
  completing the fixed-width validation family alongside `require32`.

### Changed

- Specialized built-in composite block unpackers to validate their known keys
  directly instead of constructing and evaluating generic specifications.
- Specialized fixed-width block validation, empty-block inspection, and
  key-only `takeBlock` paths to avoid redundant specification and calldata
  work.
- Pipeline execution now validates the complete STEP source and rejects a
  trailing block with a different key instead of silently stopping after the
  first homogeneous run.
- Simplified internal debit-account output allocation to use the fixed-width
  input size directly.

## 1.24.0

### Breaking Changes

- Renamed the existing `Position`-consuming `repay` and `repayPayable`
  commands to `repayPosition` and `repayPositionPayable`. Their state
  transition remains `Position` to `Balance`; the new commands using the old
  names consume `Debt` and return empty state. Command selectors and node IDs
  for position repayment therefore change.

### Added

- Added the standalone `Debt { liability, debt }` pipeline state, its standard
  block key and schema, and codec support across blocks, readers, writers,
  decoders, and execution helpers.
- Added `repay` and `repayPayable` commands that consume `Debt` state and return
  empty state.
- Added `RepayInternal` for dispatching the non-funded `repay` command directly
  against memory-backed pipeline state.
- Added unchecked `Blocks.read1`, `read2`, `read8`, and `read16` absolute
  calldata helpers, completing the power-of-two family alongside `read4` and
  `read32`.
- Added the standalone `ensureContract` utility and shared `InvalidContract`
  error for uniformly requiring addresses with deployed bytecode.
- Added the free `enforceSender` access helper for requiring an exact
  `msg.sender` with the shared `AccessDenied` error.
- Documented descriptor flag bits 6 and 7 as endpoint-defined custom flags;
  bits 2 through 5 remain reserved for future protocol flags.

### Changed

- Repayment commands now publish the canonical `Actions.Repay` annotation
  instead of `Actions.Settle`.

## 1.23.0

### Breaking Changes

- Changed every command entrypoint from
  `(bytes32 account, bytes state, bytes input)` to one `bytes context` argument
  containing exactly one encoded `CONTEXT` block. Canonical command selectors
  now use `(bytes)`, so every command node ID changes. Existing command callers,
  cached IDs, and deployed host graphs are not compatible with this release.
- Added the acting account to `Execution`. `CommandBase.openCommand` and
  `AdminBase.openAdminCommand` now accept the encoded context and return only
  the initialized execution, and command implementations close with
  `closeCommand(exec)` instead of `close(exec, account)`.
- Removed the separate state argument from `RelayPayableHook.relay`. Relay
  implementations can obtain the complete validated state with
  `exec.rawState()` while the explicit account and nested relay input arguments
  remain unchanged.
- Consolidated `AllowAssetsPort` and `DenyAssetsPort` into
  `ports/Assets.sol`; update direct source imports to the new path.
- Renamed the peer `AllowancePort` and `portAllowance` selector to
  `RequestAllowancePort` and `portRequestAllowance`. The peer port now uses a
  distinct `RequestAllowanceHook.requestAllowance` hook; the admin `Allowance`
  command and its authoritative `AllowanceHook.allowance` hook are unchanged.
- Removed the `Commander` event declaration. Commander addresses and chain
  context are off-chain configuration; host, native-asset, and admin IDs are
  deterministic from that information.
- Prefixed every typed `Blocks` factory with `create`, including calldata-copy
  variants; for example, use `createBalance`, `createStepCopy`, `createBytes`,
  and `createString` instead of `balance`, `stepCopy`, `data`, and `text`.
- Changed the `max8`, `max16`, `max24`, `max32`, `max40`, `max64`, `max96`,
  `max128`, and `max160` bounds helpers to return their corresponding narrowed
  integer types instead of `uint`.

### Added

- Added `PositionedEvent`, which publishes asset and liability sides together
  with the semantic action that produced the observed position.
- Added `RequestAssetPort`, which passes trusted peers' batched asset and amount
  requests to a host hook for validation and fulfillment.
- Added `Executions.takeBlock`, which validates and consumes a block from a
  selected decoder lane and returns its complete calldata encoding.
- Added `Executions.rawState` and `Executions.rawInput` for retrieving complete
  validated calldata lanes independently of current cursor progress.
- Added `Blocks.createAmount` for constructing canonical `AMOUNT` blocks.

### Changed

- Command pipeline hops now construct `command(bytes)` calldata and the nested
  `CONTEXT` block directly in one allocation, copying memory state and calldata
  input into the final call buffer.
- Added memory `callPort`/`tryCallPort` helpers and calldata-copy
  `callPortCopy`/`tryCallPortCopy` counterparts, matching the block factory
  naming convention. Portal forwarding and recovery use the copy variants.

### Upgrade Compatibility

- Rebuild command IDs from the new `(bytes)` selectors, redeploy command hosts,
  and update pipeline builders and other callers to pass one encoded `CONTEXT`
  block. Do not mix 1.22 command IDs or callers with 1.23 deployments.
- Update custom commands to read the acting account from `exec.account`, use
  `openCommand(context, descriptor, batches)`, and return
  `closeCommand(exec)`.
- Update relay hook implementations to remove the state parameter and use
  `exec.rawState()` when the forwarded state is required.
- Update direct port imports, renamed request-allowance endpoints and hooks,
  typed `Blocks` factory calls, and any assignments that relied on `max*`
  returning `uint`.

## 1.22.0

### Breaking Changes

- Declared child blocks are now structurally present whenever their parent is
  non-empty. A child without a value uses its zero-payload block form instead
  of being omitted. The `maybe` modifier now hints that onchain code accepts
  that empty form; it no longer describes an absent item. Lists likewise keep
  their header and represent no items with an empty payload.
- Removed `Schemas.Unit`. Use the empty form of the block key that carries the
  relevant semantic meaning instead of a generic unit marker.
- Renamed `Decoders.take(cur, key)` to `takeBlock(cur, key)`. The `take` name is
  now used by raw cursor navigation and returns the absolute start of a
  bounds-checked byte range while advancing the cursor.
- Normalized standard schema bodies by removing their presentation-only outer
  braces, and renamed the standard node field from `id` to `node`. Published
  schema annotation bytes therefore change even though their wire layouts do
  not.

### Added

- Added empty-block inspection, conditional consumption, encoding, writing,
  and execution-output helpers across `Blocks`, `Decoders`, `Readers`,
  `Writers`, and `Executions`.
- Added `absolute`, `advance`, and raw `take` cursor helpers, plus `enter`
  overloads that advance over a validated fixed payload prefix in one cursor
  update.
- Added unnamed `schema` overloads for context-local specifications and an
  unnamed `Blocks.schema` factory overload.
- Added the offchain-only `at N` schema projection hint. Explicit positions are
  reserved first, then unannotated siblings fill the remaining positions in
  declaration order; wire encoding and onchain decoding remain unchanged.

### Changed

- Clarified that one optional pair of outer braces is presentation-only for all
  non-empty schema bodies, including custom top-level `many` schemas.
- Updated custom input examples to group fixed-width fields for direct calldata
  reads, demonstrate empty child blocks, and separate top-level and nested swap
  decoding.
- Excluded repository documentation and examples from the prepared npm package;
  the package continues to contain Solidity sources, the README, changelog, and
  license.

### Upgrade Compatibility

- Emit every declared child header in schema order. When a `maybe` child has no
  value, emit that child's key with a zero payload length and call
  `tryConsumeEmpty` before its strict semantic unpacker.
- Replace `Schemas.Unit` markers with an empty block carrying the key expected
  by the receiving schema.
- Replace `cur.take(key)` with `cur.takeBlock(key)`. Use `cur.take(amount)` only
  for raw fixed-width ranges.
- Indexers should accept braced and unbraced schema bodies, treat `maybe` as an
  empty-value hint, and apply `at N` only after decoding declaration-order wire
  data.

## 1.21.0

### Breaking Changes

- Repacked endpoint descriptors as `[state key:4][stride:1]`,
  `[input key:4][stride:1]`,
  `[output key:4][min:4][max:4][hint:3][stride:1]`, four reserved bytes,
  one transaction-count byte, and one flags byte. The input child-key field was
  removed; indexers and request builders must decode the new layout.
- Removed container metadata and the `many` and `keys` helpers from `Specs`.
  Top-level lists are now emitted custom schemas whose context-local key is the
  endpoint input key; nested lists continue to use the generic `#list` key.
- Replaced the `funded` and `admin` boolean parameters on command helpers and
  the `funded` boolean parameter on port helpers with a packed `uint8 flags`
  argument. Endpoint flags now live in the dedicated `Flags` library.
- Renamed the portal lifecycle events from `Undelivered` and `Recovered` to
  `Unresolved` and `Resolved`, and renamed `Portal.retry` to `Portal.resolve`.
  `Portal` now composes the node-access, runtime, and lifecycle-event
  capabilities; concrete implementations remain responsible for explicitly
  emitting lifecycle events.

### Added

- Added custom-spec overloads for `Decoders.list(cur, spec)` and
  `Executions.list(exec, spec, lane)` so custom-keyed top-level lists can use
  the same cursor model as generic nested lists.
- Added `Specs.lane` for canonical descriptor lane packing and exported
  `Flags` from the codec, command, and endpoint package entry points.

### Changed

- Updated schema and indexing documentation and the list example for the
  custom-keyed top-level list convention.

## 1.20.0

### Breaking Changes

- `Nodes.toCommand`, `toPort`, `toQuery`, and `toGuard` now take an endpoint
  name instead of a precomputed selector. The `Selectors` library was removed;
  endpoint node IDs now derive their canonical selectors internally.
- Renamed the memory-backed pipeline adapters from `InternalDebitAccount`,
  `InternalCreditAccount`, and `InternalSettle` to `DebitAccountInternal`,
  `CreditAccountInternal`, and `SettleInternal`.
- Replaced `RelayPayableHook.relayTo(portal, resources, payload, funds)` with
  `relay(portal, resources, account, state, input, funds)`. Relay commands now
  pass their semantic context fields to the host instead of encoding a
  `CONTEXT` payload before invoking the hook.
- `DispatchPayablePort` now uses the dedicated
  `DispatchPayableHook.dispatchTo(portal, resources, payload, funds)` hook
  instead of sharing `RelayPayableHook`.

### Added

- Added `RelayEvent`, with account, portal, resources, correlation key, and
  digest fields for recording outbound relay references.

### Changed

- Relay hooks retain state and nested relay input as calldata until an
  implementation chooses to encode or otherwise consume the destination
  context.

### Upgrade Compatibility

- Pass endpoint names directly to the `Nodes.to*` helpers and remove imports of
  `Selectors`.
- Update inherited internal adapter names and imports to the new postfix
  convention.
- Implement the structured `RelayPayableHook.relay` hook for relay commands and
  `DispatchPayableHook.dispatchTo` for opaque dispatch payloads. Hosts that
  support both surfaces must implement both hooks.

## 1.19.0

### Breaking Changes

- Renamed port endpoint contracts from the `Port*` prefix convention to the
  `*Port` postfix convention: `PortAllowAssets`, `PortAllowance`,
  `PortCreditAccount`, `PortDebitAccount`, `PortDenyAssets`,
  `PortDispatchPayable`, `PortPipePayable`, `PortPost`, and
  `PortRedeemBalance` are now `AllowAssetsPort`, `AllowancePort`,
  `CreditAccountPort`, `DebitAccountPort`, `DenyAssetsPort`,
  `DispatchPayablePort`, `PipePayablePort`, `PostPort`, and
  `RedeemBalancePort` respectively. Endpoint selectors are unchanged.
- Removed `Blocks.readUint`; cast `uint(Blocks.read32(abs))` when an unchecked
  absolute word read is required, or use the new cursor-consuming `next32`
  helpers while decoding.
- `Cursors.advance` and `Cursors.slice` now assume the documented packed-cursor
  invariant `i <= len` instead of pre-validating manually constructed cursor
  words. Invalid raw cursor words may now produce an arithmetic panic rather
  than `Cursors.OutOfBounds`.

### Added

- Added `enter` and `expectAbs` to `Decoders` and `Executions` for entering a
  parent payload, decoding its children in place, and proving exact final
  consumption.
- Added consuming `next1`, `next2`, `next4`, `next8`, `next16`, and `next32`
  helpers to `Decoders` and `Executions` for compact fixed-width schema fields.
- Added calldata-copy encoding across `Buffers`, `Blocks`, `Writers`, and
  `Executions`. In-place helpers use `copy*`, execution helpers use
  `outputCopy*`, and allocating block factories use the `*Copy` suffix.
- Added allocating factories for LIST, EVM, CONTEXT, and RECOVER blocks, plus
  memory and calldata factory pairs for dynamic leaf and composite blocks.

### Changed

- Block factories now allocate once and delegate to their canonical `write*`
  or `copy*` encoder instead of assembling nested intermediate byte arrays.
- Relay and dispatch paths preserve calldata slices until their destination
  requires memory, avoiding unnecessary explicit calldata-to-memory casts.
- `Settlement.settle` now implements its documented behavior by routing the
  liability leg through the virtual `repay` primitive before crediting the
  asset leg.
- Documented that restricting schema `bytesN` fields to power-of-two widths is
  under consideration; all widths from `bytes1` through `bytes32` remain valid.

### Upgrade Compatibility

- Update inherited port contract names and their imports to the new `*Port`
  names. No endpoint selector or wire-format migration is required.
- Replace `Blocks.readUint(abs)` with `uint(Blocks.read32(abs))`, or migrate
  sequential custom decoders to `enter`, `next*`, and `expectAbs`.
- Code that constructs packed cursors manually must establish `i <= len`
  before calling navigation helpers. Normal cursor constructors and composition
  helpers already preserve this invariant.
- `Settlement` subclasses that override `repay` will now have that override
  invoked by `settle`, matching the documented extension point.

## 1.18.0

### Added

- Added the non-funded `repay` and funded `repayPayable` commands. Both consume
  `Position` state, settle only its liability side, and return the released
  asset side as `Balance` state.
- Added the reusable non-funded `RepayHook` settlement primitive and the
  execution-funded `RepayPayableHook`.
- Added the opt-in `RevokeAsset` guardian endpoint, which accepts `Asset`
  entries and denies each asset through the existing `DenyAssetsHook`.

### Changed

- `Settlement.settle` now delegates its liability leg to the virtual `repay`
  primitive. The default behavior remains a nonzero `debitAccount` call, while
  derived settlement implementations can customize repayment in one place.
- Exported the repayment commands and hooks and the asset-revocation guard from
  their corresponding public barrels.

### Upgrade Compatibility

- Hosts inheriting `Settlement` retain the previous default settlement
  behavior. Hosts that already declare an internal
  `repay(bytes32,bytes32,uint)` function may need to mark it as an override or
  rename it when upgrading.

## 1.17.0

### Breaking Changes

- `executeDebitAccount`, `executeCreditAccount`, and `executeSettle` now require
  the pipeline step's `uint128 value` argument and reject nonzero value inside
  the internal adapter.
- `AllowanceHook` implementations must treat an amount of zero as revocation.

### Added

- Added the `HostAsset` structural block and complete codec support for
  host-scoped asset references.
- Added the opt-in `RevokeAllowance` guardian endpoint, which accepts
  `HostAsset` entries and revokes each allowance through `AllowanceHook`.
- Added the funded `settlePayable` command and `SettlePayableHook` for settlement
  implementations that require access to the command's native-value budget.

### Changed

- Completed the endpoint barrel with `CommandBase` and exported the new command,
  guard, hook, internal adapter, and structural type surfaces from their
  corresponding package barrels.

### Upgrade Compatibility

- Pipeline hosts using the internal debit, credit, or settle adapters must pass
  each step's assigned value into the adapter. Existing non-funded steps should
  continue to pass zero.

## 1.16.0

### Breaking Changes

- Removed the unused generic `Position` event and `PositionEvent` base contract.
- Renamed transaction handling from settlement to posting: the transaction
  helper is now `post(...)`, and `portSettle(bytes)` is now `portPost(bytes)`.
  The port selector and node ID change, and its action is now `Actions.Post`
  (`14`) instead of `Actions.Settle` (`3`). The `Settlement` convenience base
  implements both the transaction `PostHook` and position `SettleHook`.
- Removed `openInput` from `EndpointBase`. Port, query, and guard bases expose
  `openInput` through the input-only `InputEndpointBase`, while custom commands
  must pass both state and input through `openCommand`.
- Removed the wildcard `Specs.Any` state type. The stateful relay is now
  `relayBalancePayable` and accepts `BALANCE` state blocks; `relayPayable`
  explicitly accepts empty state.
- Renamed the numeric `Position` fields from `assets` and `liabilities` to
  `amount` and `debt`.
- Renamed `Budget.use` to `useResourceValue` and split execution spending into
  exact `useValue` and packed-resource `useResourceValue` helpers.
- Renamed `RoutePayableHook.route` to `RelayPayableHook.relayTo`. Recovery hooks
  are now `RecoverPayableHook` implementations that receive the complete
  resource word and mutable execution budget.

### Added

- Added the hostless `#position` state block for threading asset-liability pairs
  between pipeline commands.
- Added the `settle` command, the position `SettleHook`, and the transaction
  `PostHook`. The `Settlement` convenience base provides default implementations
  of both through the debit and credit account hooks.
- Added `relayBalancePayable` for relaying required `BALANCE` state while
  `relayPayable` now explicitly relays with empty state.
- Added memory-backed `InternalDebitAccount`, `InternalCreditAccount`, and
  `InternalSettle` adapters for hosts that execute canonical commands directly
  from their pipeline dispatcher.

### Changed

- Documented the command state-safety invariant: every command must handle the
  complete supplied state stream or revert, and commands with empty state lanes
  must reject non-empty state.
- Endpoint decoder opening now requires the complete supplied lane to be one
  homogeneous run of the descriptor's declared key; trailing block types are
  rejected instead of silently left outside the decoder cursor.
- Block runs and cursors now retain raw block counts only. Descriptor stride
  conversion and state/input group reconciliation happen once in execution
  opening rather than in `Blocks` or `Cursors`.
- Pipeline transaction streams are posted before the next step, and position
  state is settled separately through the scalar asset, amount, liability, and
  debt hook.
- Completed the public barrel exports for internal command adapters,
  input-only endpoint bases, access errors, and low-level utility helpers.

### Upgrade Compatibility

- Command and port selectors, block schemas, and hook signatures changed in
  this release. Deploy fresh hosts and update pipeline builders and peer
  integrations together.

## 1.15.0

### Breaking Changes

- Replaced the monolithic `AccessControl` base with the composable
  `CommanderAccess`, `AdminAccess`, `NodeAccess`, `GuardianAccess`,
  `CallerAccess`, and `TrustAccess` capabilities. `CommandBase` now requires a
  concrete caller policy and no longer inherits outbound `NodeCalls`.
- Split host composition into the commander-only `CommandHost`, the advanced
  `Host`, and the optional `Admins` and `Guardians` feature bundles. Commands
  that use trusted outbound calls must now inherit `NodeCalls` directly and
  compose a `TrustAccess` implementation.
- Removed the guardian account subtype. Guardians are now ordinary user
  accounts assigned a host-local role, so previously encoded guardian account
  IDs are not compatible.
- Replaced the `Labeled` and `Schema` discovery events and their dedicated admin
  commands with typed blocks in the generic `Annotation` event and the
  `annotate` admin command.
- Added the origin user account to `Introduction`, changing its event signature
  to `Introduction(uint indexed host, uint peer, bytes32 origin, uint blocknum)`.

### Added

- Added opt-in `Label`, `Schema`, and `Action` annotation mixins together with
  canonical `#label`, `#schema`, `#annotation`, and `#action` codec support.
- Added semantic action annotations to deposit, payable deposit, withdrawal,
  burn, payout, and port settlement endpoints.

### Changed

- Enabled the Solidity optimizer with 200 runs and pinned release testing to
  the Cancun EVM target, the minimum target supporting the codec's `MCOPY` use.
- Guardians can revoke node access but remain unable to grant it; admin
  commands continue to require both the immutable commander caller and its
  derived admin account.

### Upgrade Compatibility

- Existing deployments are not upgradeable and this release does not preserve
  storage layout or guardian mapping keys for proxy upgrades. Deploy fresh host
  contracts when adopting this version.

## 1.14.0

### Breaking Changes

- Replaced `CommandContext` and the separate payable value lifecycle with the
  unified `Execution` context. Endpoint and command implementations now open an
  execution directly from calldata, use its packed decoder and writer lanes,
  and finish through the shared `close` helpers.
- Reworked the block codec around absolute-position `Blocks` primitives,
  packed `Cursors`, cursor-backed `Decoders`, lazy `Buffers`, and thin
  `Writers`. Several low-level cursor and writer APIs were renamed or removed.
- Redefined block specs and endpoint descriptors. Specs now encode key, minimum,
  maximum, allocation hint, stride, and optional LIST container metadata;
  descriptors use normalized lane specs and include a transaction stride.
- Replaced the `Cursors.sol` package entry point with `Codec.sol`, added the
  command-authoring `Commands.sol` entry point, and reorganized exports across
  the package barrels.
- Endpoint selectors are now derived from endpoint names. The configured name
  must match the implementing function name, and descriptor values are
  represented as `uint` throughout.
- Removed the AUTH and BOUNTY codec blocks, the obsolete `Payable`/`Values`
  helpers, and superseded decoder, writer, schema, and descriptor overloads.

### Added

- Added packed output and transaction writer lanes to `Execution`, including
  semantic output helpers, queued credit/debit transactions, budget refunds,
  and direct transaction finalization.
- Added detachable `Budget` values for pipeline-style consumers, shared lane
  identifiers, spec-driven writer allocation, and optimized semantic block
  readers, writers, and composite unpackers.
- Added a transaction-output example, command and codec barrel import examples,
  and expanded coverage for packed cursors, buffers, descriptors, budgets,
  execution output, and command flows.

### Changed

- Standardized command, query, guard, and port implementations on the same
  execution open/close lifecycle and renamed request terminology to input.
- Expanded NatSpec across the new execution and codec APIs and refreshed the
  protocol, schema, indexing, and multi-chain documentation.

## 1.13.0

### Breaking Changes

- Replaced the virtual `Pipeline.settle(bytes transactions)` stream hook with
  decoded settlement through `Settlement`. Pipeline implementations now provide
  `debitAccount` and `creditAccount` hooks, while the pipeline decodes each
  returned TRANSACTION block and settles it before dispatching the next step.
- Moved `DebitAccountHook` and `CreditAccountHook` from their command modules to
  `core/Settlement.sol`. They remain available from the `Core.sol` and
  `Endpoints.sol` package entry points.

### Added

- Added the memory-backed `Reader` and `Readers` block-stream API with balance
  and transaction unpackers, bounds and block validation, and positive
  iteration through `more()`.
- Added the shared `Settlement` core mixin used by pipelines and `PortSettle` to
  debit transaction sources and credit destinations.

### Changed

- Unified pipeline and port transaction handling through `Settlement`,
  including zero-account handling and zero-amount no-op settlement.

## 1.12.0

### Breaking Changes

- Removed `Keys.Local` and replaced `EndpointBase.localSchema(...)` with the
  explicit `EndpointBase.schema(uint32 key, string body)` helper for
  context-local endpoint schemas.
- Changed `Introduction` to emit the receiving `host` and introduced `peer`:
  `Introduction(uint indexed host, uint peer, uint blocknum)`.
- Replaced `isDebitAccount`, `isCreditAccount`, `isAuthorize`, and
  `isUnauthorize` helper predicates with internal command ID fields:
  `debitAccountId`, `creditAccountId`, `authorizeId`, and `unauthorizeId`.

### Added

- Added the `EndpointBase.schema(...)` helper for publishing local endpoint
  schemas.
- Added the standard `#schema` block, `unpackSchema`, and an opt-in
  `publishSchema` admin command for emitting schema claims from `#schema`
  blocks.

### Changed

- Updated the schema DSL documentation to allow any number of child blocks in
  declaration order, including fixed fields before, after, or between child
  blocks.

## 1.11.0

### Breaking Changes

- Replaced the separate command, port, query, guard, and admin discovery events
  with the shared `Endpoint` event and a packed endpoint descriptor. Admin
  commands are now identified by the descriptor admin flag. Default lane groups
  remain encoded as zero and are interpreted as group size one when read; the
  final four descriptor bytes are reserved.
- Renamed the block discovery event to `Schema` and added a `name` field for
  alias-style schema references.
- Removed the generic `DATA` block type. Custom input blocks should define
  their own local keys and publish schemas explicitly when they need discovery.
- Removed the built-in admin `init` and `destroy` commands.
- Removed the built-in `Positions` query; custom position output should be
  modeled as a custom query.
- Changed `Cursors.list` to consume the LIST block and return a cursor scoped
  to its payload instead of returning the list's end offset.
- Renamed the `CommandContext.request` field to `input`. The tuple layout and
  command selectors are unchanged.

## 1.10.0

### Breaking Changes

- Moved `RecoverHook` from `Portal.sol` to `commands/Recover.sol`.
- Moved `RoutePayableHook` from `Portal.sol` to `commands/Relay.sol`.
- Renamed Portal helpers to `forward` / `retry`; hosts now explicitly bridge
  the `RecoverPayable` hook to Portal retry behavior.
- Renamed the generic `Resolved` event to `Recovered`.
- Portal no longer emits `Recovered` when retrying an undelivered witness.
- Renamed `Cursors.exit` to `ensureAt` and renamed its position argument to
  `pos`.
- Removed the redundant `next` return value from both `Decoders.init` overloads;
  callers should use the returned cursor's `len` as the run boundary.
- Changed `Cursors.list` to require the expected current cursor position as
  `pos` before entering the LIST block.

## 1.9.0

### Breaking Changes

- Renamed relay and dispatch routing fields from `chain` to `portal` across
  schemas, cursor helpers, dispatch hooks, and dispatch/route events.
- Replaced the context-specific `RecoverContextPayable` / `#contextRecovery`
  surface with generic `RecoverPayable` / `#recover` using byte witnesses.
- Renamed the `Dispatch` event correlation field from `ref` to `key`.
- Replaced `DispatchPayableHook.dispatch` with `RoutePayableHook.route` in the
  portal core layer.
- Added `status` to `Route(uint indexed host, uint portal, uint status)`
  so routes can be removed by emitting zero status.
- Added `Undelivered(uint indexed host, bytes32 key, bytes32 digest)` for portal
  messages that could not be delivered to their handler port.
- Added `Recovered(uint indexed host, bytes32 key)` as the
  matching event for resolved undelivered digests.
- Removed the generic `Commitments` core mixin and `Commitment` event in favor
  of domain-specific events such as `Undelivered` and `Recovered`.

## 1.8.0

### Breaking Changes

- Removed per-port `IPort*` interfaces. Port callers should use port node IDs,
  discovery metadata, and `PortCalls.callPort`.
- Removed unused standalone ABI encoder helpers: `encodePortCall`,
  `encodeGuardCall`, and `encodeQueryCall`.
- Reworked `NodeCalls` into a low-level node-call layer:
  - `callAddr` and `queryAddr` were removed.
  - `callTo` and `queryTo` were removed.
  - Raw node calls now use `rawCall`, `tryRawCall`, and `rawQuery`.

### Added

- Added `trustedCall`, `tryTrustedCall`, and `trustedQuery` as shared trusted
  wrappers over the raw node-call helpers.
- Added `CommandCalls.callCommand` and `PortCalls.callPort` for selector-based
  trusted calls to command and port nodes.

## 1.7.0

### Breaking Changes

- Renamed peer callable surfaces to ports:
  - `contracts/peer` moved to `contracts/ports`.
  - `PeerEvent` / `event Peer` became `PortEvent` / `event Port`.
  - `PeerBase`, `IPeer*`, and `Peer*` endpoint contracts became `PortBase`,
    `IPort*`, and `Port*`.
  - Peer endpoint functions and labels now use `port*` names, such as
    `portPipePayable`, `portDispatchPayable`, and `portSettle`.
  - Node helpers and layout tags now use `Port` terminology:
    `Nodes.toPort`, `Nodes.isPort`, `Nodes.port`, and
    `Nodes.portSelector`.
- Removed the generic `PortRecoverContextPayable`; recovery is now routed by
  the command-level `recoverContextPayable` to concrete ports such as
  `portPipePayable`.
- Renamed the `#contextRecovery` handler field from `target` to `port`.
- Changed port entrypoint calldata parameter naming to `data` to avoid
  clashing with nested context `request` fields.

### Added

- Added `RecoverContextPayable` and `#contextRecovery` for command-level
  recovery routing with a commitment key, resources, handler port, and context
  witness.
- Added `Dispatch(uint indexed host, uint chain, uint resources, bytes32 digest, bytes32 ref)`
  as the discovery/event surface for dispatch tracking.
- Added `ContextRecovery` schema/cursor support and context schema aliases for
  reusable nested block schemas.
- Added `Values.drain`, `Payable.openValue`, and `Payable.end` to make
  payable command budget lifecycles explicit.

## 1.6.0

### Added

- Added `AdminBase` as the shared base for admin commands and exported it from
  `Endpoints.sol`.
- Added `Cursors.read1` and `Cursors.read2` for unchecked byte-sized calldata
  reads.
- Added `NativeAsset` as a reusable base for helpers that need the local native
  asset ID without the full host runtime.
- Added `Escrows` as a keyed ledger for amounts reserved outside normal
  balances.
- Added `Commitment(uint indexed host, bytes32 key, bytes32 digest, uint status)`
  and the `Commitments` core mixin for digest commitments and witness/recovery
  flows.

## 1.5.0

### Breaking Changes

- Refactored account, asset, and node IDs around the shared convention that
  first byte `0x00` means opaque and nonzero means structured.
- Replaced the previous generic ID helpers with `Nodes` for structured host,
  chain, command, peer, query, and guard node IDs.
- Changed assets to single-word IDs: `bytes32 asset` is now the unique asset key
  without a separate metadata field or asset slot.
- `Payout` now passes destination accounts through to the hook unchanged; payout
  account policy is the hook implementation's responsibility.

### Added

- Added `Ids` as the shared helper library for opaque IDs, including
  `Ids.isOpaque`, `Ids.opaque`, `Ids.toKeccak`, and `Ids.matchKeccak`.
- Added opaque account, asset, and node helper wrappers in `Accounts`, `Assets`,
  and `Nodes`.
- Added `Asset(uint indexed host, bytes32 asset, bytes preimage)` for declaring
  opaque asset preimages.
- Documented opaque preimages as `[formatHash:1][payload...]`, where `0x01`
  means keccak256.

## 1.4.0

### Breaking Changes

- Replaced the `Chain` discovery event with `Commander(uint indexed host, uint chain, bytes32 native, bytes32 admin)`.
- Removed the `Transfer` flow event; account flows should be represented with `Spent` and `Received`.
- Renamed the indexed `Labeled` event parameter from `id` to `entity` in the published ABI string.

### Added

- Added `Route(uint indexed host, uint chain, uint context)` for generic cross-chain route discovery.
- Added `Actions.Refund` for unused payable command value returned through settlement hooks.

## 1.3.0

### Breaking Changes

- Simplified `Decoders.init` to parse a single run from the start of a calldata slice. Callers that previously passed an offset must slice first or use `Decoders.open(source, i)`.
- Tightened command, query, and peer request parsing around the single-run convention used by current protocol endpoints.

### Added

- Added `peerCreditTo` and `peerDebitFrom` peer endpoints for account-scoped `ACCOUNT_AMOUNT` batches.
- Added same-file `IPeer*` interfaces for every peer endpoint and exported them from `Endpoints.sol`.
- Added indexing documentation covering discovery, labels, access state, balance events, and flow-event conventions.

## 1.2.0

### Breaking Changes

- Removed human-readable names from Command, Admin, Peer, Query, Guard, and Chain discovery events.
- Added the Labeled event and default labels for commands, admin commands, peers, queries, guards, and examples.
- Added LABEL and STRING block schemas, plus cursor helpers for decoding labels supplied by callers.
- Added the admin label command for publishing mutable namespaced labels.
- Removed version and namespace fields from host Introduction events and host constructor introductions.

## 1.1.0

### Breaking Changes

- Renamed local execution fields from `value` to `resources` in PIPE, CALL, and STEP schemas.
- Interprets EVM value as the low 128 bits of packed `resources`.
- Changed native value APIs and dispatch hooks to use `uint128` for actual EVM value.
- Replaced the relay-specific hook with shared `DispatchPayableHook`.
- `RelayPayable` now dispatches an encoded PIPE payload and settles leftover user command value.
