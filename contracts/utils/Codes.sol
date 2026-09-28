// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Actions} from "./Actions.sol";
import {States} from "./States.sol";

/// @notice Reusable packed combinations of canonical code identifiers.
/// @dev Combinations are uint words, not new uint32 identifiers or bit flags.
/// The action occupies the lowest slot, followed by the resulting state.
/// Hosts may define additional combinations using the same packing convention.
library Codes {
    // Membership.
    /// @dev An existing subject was added and is active in the resulting state.
    uint constant AddThenActive = uint(Actions.Add) | (uint(States.Active) << 32);
    /// @dev A subject was removed and is inactive in the resulting state.
    uint constant RemoveThenInactive = uint(Actions.Remove) | (uint(States.Inactive) << 32);

    // Availability.
    /// @dev A configured subject was enabled and is active in the resulting state.
    uint constant EnableThenActive = uint(Actions.Enable) | (uint(States.Active) << 32);
    /// @dev A configured subject was disabled and is inactive in the resulting state.
    uint constant DisableThenInactive = uint(Actions.Disable) | (uint(States.Inactive) << 32);

    // Authorization.
    /// @dev A subject was authorized and is active in the resulting state.
    uint constant AuthorizeThenActive = uint(Actions.Authorize) | (uint(States.Active) << 32);
    /// @dev A subject's authorization was revoked and is inactive in the resulting state.
    uint constant RevokeThenInactive = uint(Actions.Revoke) | (uint(States.Inactive) << 32);

    // Roles.
    /// @dev A subject was appointed and is active in the resulting state.
    uint constant AppointThenActive = uint(Actions.Appoint) | (uint(States.Active) << 32);
    /// @dev A subject was dismissed and is inactive in the resulting state.
    uint constant DismissThenInactive = uint(Actions.Dismiss) | (uint(States.Inactive) << 32);

    // Asset support.
    /// @dev A subject was allowed and is active in the resulting state.
    uint constant AllowThenActive = uint(Actions.Allow) | (uint(States.Active) << 32);
    /// @dev A subject was denied and is inactive in the resulting state.
    uint constant DenyThenInactive = uint(Actions.Deny) | (uint(States.Inactive) << 32);
}
