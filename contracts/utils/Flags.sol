// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @title Flags
/// @notice Public endpoint behavior flags encoded in endpoint IDs.
/// @dev Bits 2-5 are logging policy flags defined by Logs; bit 6 is endpoint-defined.
/// Logging and behavior share the endpoint ID flags byte.
library Flags {
    /// @dev Endpoint accepts nonzero native value.
    uint8 internal constant Funded = 1 << 0;
    /// @dev Endpoint is restricted to the admin account.
    uint8 internal constant Admin = 1 << 1;
    /// @dev Endpoint accepts nonzero native value and is restricted to the admin account.
    uint8 internal constant AdminFunded = Admin | Funded;
    /// @dev Endpoint takes ownership of the remaining pipeline steps.
    uint8 internal constant Handoff = 1 << 7;
    /// @dev Endpoint accepts nonzero native value and takes ownership of the remaining pipeline steps.
    uint8 internal constant HandoffFunded = Handoff | Funded;
}
