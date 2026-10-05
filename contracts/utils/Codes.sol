// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Actions} from "./Actions.sol";
import {Entities} from "./Entities.sol";
import {States} from "./States.sol";

/// @notice Reusable packed combinations of canonical code identifiers.
/// @dev Combinations are uint words, not new uint32 identifiers or bit flags.
/// Slots are packed from the lowest uint32 upward. Scoped log combinations put
/// the scope entity kind first; the remaining order is defined by each combination.
/// The event family defines where the actual scope and subject IDs are found.
/// Legacy unscoped combinations below retain their existing order and meaning.
library Codes {
    // Host-scoped recovery records. RESOLUTION identifies key and message digest.
    uint constant HostUnresolved = Entities.Host | (States.Unresolved << 32);
    uint constant HostResolved = Entities.Host | (States.Resolved << 32);

    // Host-scoped discovery claims. INTRODUCTION identifies the introducing peer.
    uint constant HostIntroduce = Entities.Host | (Actions.Introduce << 32);

    // Host-scoped registration. The block schema identifies the subject kind.
    uint constant HostAdd = Entities.Host | (Actions.Add << 32);

    // Host-scoped metadata claims. ANNOTATION blocks identify the subjects.
    uint constant HostAnnotate = Entities.Host | (Actions.Annotate << 32);

    // Host-scoped authorization. NODE blocks identify the affected subjects.
    uint constant HostAuthorizeThenActive = Entities.Host | (Actions.Authorize << 32) | (States.Active << 64);
    uint constant HostRevokeThenInactive = Entities.Host | (Actions.Revoke << 32) | (States.Inactive << 64);

    // Host-scoped guardian membership. ACCOUNT blocks identify the guardians.
    uint constant HostAppointGuardianThenActive = Entities.Host | (Entities.Guardian << 32) | (Actions.Appoint << 64) | (States.Active << 96);
    uint constant HostDismissGuardianThenInactive = Entities.Host | (Entities.Guardian << 32) | (Actions.Dismiss << 64) | (States.Inactive << 96);

    // Host-scoped configuration. Input schemas identify assets and allowances.
    uint constant HostUpdate = Entities.Host | (Actions.Update << 32);
    uint constant HostAllowThenActive = Entities.Host | (Actions.Allow << 32) | (States.Active << 64);
    uint constant HostDenyThenInactive = Entities.Host | (Actions.Deny << 32) | (States.Inactive << 64);

    // Host-scoped pools. Consecutive input pairs identify each pool.
    uint constant HostAddPool = Entities.Host | (Entities.Pool << 32) | (Actions.Add << 64);
    uint constant HostRemovePool = Entities.Host | (Entities.Pool << 32) | (Actions.Remove << 64);

    // Asset-scoped metadata claims. ASSET_PREIMAGE supplies the asset and preimage.
    uint constant AssetAnnotate = Entities.Asset | (Actions.Annotate << 32);

    // Account operations: account entity followed by the action.
    uint constant AccountPayout = Entities.Account | (Actions.Payout << 32);
    uint constant AccountDeposit = Entities.Account | (Actions.Deposit << 32);
    uint constant AccountWithdraw = Entities.Account | (Actions.Withdraw << 32);
    /// @dev Credit remaining native value to the account; BALANCE carries the credited amount.
    uint constant AccountCashin = Entities.Account | (Actions.Cashin << 32);
    uint constant AccountCashout = Entities.Account | (Actions.Cashout << 32);
    uint constant AccountBurn = Entities.Account | (Actions.Burn << 32);
    uint constant AccountRealize = Entities.Account | (Actions.Realize << 32);
    uint constant AccountSettle = Entities.Account | (Actions.Settle << 32);
    uint constant AccountCredit = Entities.Account | (Actions.Credit << 32);
    uint constant AccountDebit = Entities.Account | (Actions.Debit << 32);
    uint constant AccountBootstrap = Entities.Account | (Actions.Bootstrap << 32);
    uint constant AccountRepay = Entities.Account | (Actions.Repay << 32);

    /// @dev A route was added and is active in the resulting state.
    uint constant AddRouteThenActive = Actions.Add | (Entities.Route << 32) | (States.Active << 64);
    /// @dev A route was removed and is inactive in the resulting state.
    uint constant RemoveRouteThenInactive = Actions.Remove | (Entities.Route << 32) | (States.Inactive << 64);

    // Membership.
    /// @dev An existing subject was added and is active in the resulting state.
    uint constant AddThenActive = Actions.Add | (States.Active << 32);
    /// @dev A subject was removed and is inactive in the resulting state.
    uint constant RemoveThenInactive = Actions.Remove | (States.Inactive << 32);

    // Availability.
    /// @dev A configured subject was enabled and is active in the resulting state.
    uint constant EnableThenActive = Actions.Enable | (States.Active << 32);
    /// @dev A configured subject was disabled and is inactive in the resulting state.
    uint constant DisableThenInactive = Actions.Disable | (States.Inactive << 32);

    // Authorization.
    /// @dev A subject was authorized and is active in the resulting state.
    uint constant AuthorizeThenActive = Actions.Authorize | (States.Active << 32);
    /// @dev A subject's authorization was revoked and is inactive in the resulting state.
    uint constant RevokeThenInactive = Actions.Revoke | (States.Inactive << 32);

    // Roles.
    /// @dev A subject was appointed and is active in the resulting state.
    uint constant AppointThenActive = Actions.Appoint | (States.Active << 32);
    /// @dev A subject was dismissed and is inactive in the resulting state.
    uint constant DismissThenInactive = Actions.Dismiss | (States.Inactive << 32);

    // Asset support.
    /// @dev A subject was allowed and is active in the resulting state.
    uint constant AllowThenActive = Actions.Allow | (States.Active << 32);
    /// @dev A subject was denied and is inactive in the resulting state.
    uint constant DenyThenInactive = Actions.Deny | (States.Inactive << 32);
    /// @dev An asset was allowed and is active in the resulting state.
    uint constant AllowAssetThenActive = Actions.Allow | (Entities.Asset << 32) | (States.Active << 64);
    /// @dev An asset was denied and is inactive in the resulting state.
    uint constant DenyAssetThenInactive = Actions.Deny | (Entities.Asset << 32) | (States.Inactive << 64);
}
