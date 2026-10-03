// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Actions} from "./Actions.sol";
import {Entities} from "./Entities.sol";
import {States} from "./States.sol";

/// @notice Reusable packed combinations of canonical code identifiers.
/// @dev Combinations are uint words, not new uint32 identifiers or bit flags.
/// The action occupies the lowest slot, followed by the optional entity kind
/// and the resulting state. Existing two-slot combinations omit the kind.
/// Hosts may define additional combinations using the same packing convention.
library Codes {
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
