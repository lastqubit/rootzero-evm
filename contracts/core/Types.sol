// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @notice Asset and amount pair used across ledger, command, and block flows.
struct AssetAmount {
    /// @dev Asset identifier.
    bytes32 asset;
    /// @dev Token amount in the asset's native units.
    uint amount;
}

/// @notice Asset and liability identifier pair used to select a position shape.
struct AssetLiability {
    /// @dev Identifier for the asset side.
    bytes32 asset;
    /// @dev Identifier for the liability side.
    bytes32 liability;
}

/// @notice Account-scoped asset shape.
struct AccountAsset {
    /// @dev Account identifier.
    bytes32 account;
    /// @dev Asset identifier.
    bytes32 asset;
}

/// @notice Account-scoped amount shape for inputs, responses, and reporting.
struct AccountAmount {
    /// @dev Account identifier.
    bytes32 account;
    /// @dev Asset identifier.
    bytes32 asset;
    /// @dev Token amount in the asset's native units.
    uint amount;
}

/// @notice Host-scoped asset shape.
struct HostAsset {
    /// @dev Host node identifier.
    uint host;
    /// @dev Asset identifier.
    bytes32 asset;
}

/// @notice Host-scoped asset and amount shape.
struct HostAmount {
    /// @dev Host node identifier.
    uint host;
    /// @dev Asset identifier.
    bytes32 asset;
    /// @dev Token amount in the asset's native units.
    uint amount;
}

/// @notice Host-scoped account asset shape.
struct HostAccountAsset {
    /// @dev Host node identifier.
    uint host;
    /// @dev Account identifier.
    bytes32 account;
    /// @dev Asset identifier.
    bytes32 asset;
}

/// @notice Host-scoped account amount shape.
struct HostAccountAmount {
    /// @dev Host node identifier.
    uint host;
    /// @dev Account identifier.
    bytes32 account;
    /// @dev Asset identifier.
    bytes32 asset;
    /// @dev Token amount in the asset's native units.
    uint amount;
}

/// @notice Constraints on a resulting position's asset, liability, and quantities.
/// @dev Asset and liability identifiers must match exactly. Quantity bounds are
/// inclusive and do not constrain the position's counterparty.
struct Quote {
    /// @dev Required asset identifier.
    bytes32 asset;
    /// @dev Required liability identifier.
    bytes32 liability;
    /// @dev High 128 bits: minimum net asset receipt; low 128 bits: maximum total
    /// debt including fees. Both bounds are literal, with no sentinel values.
    uint limits;
}

/// @notice Asset and liability pair threaded as live pipeline state.
/// Either side may be absent by setting both its identifier and quantity to zero.
struct Position {
    /// @dev Identifier for the asset side.
    bytes32 asset;
    /// @dev Final net asset receipt for settlement; producer fees are already accounted for.
    uint amount;
    /// @dev Identifier for the liability side.
    bytes32 liability;
    /// @dev Final total liability payment for settlement; producer fees are already accounted for.
    uint debt;
    /// @dev Settlement counterparty: Rootzero (zero) or an account ID, including a host account.
    bytes32 counterparty;
}

/// @notice Transfer payload used by transaction blocks and peer posting.
struct Tx {
    /// @dev Sender account identifier.
    bytes32 from;
    /// @dev Destination account identifier.
    bytes32 to;
    /// @dev Asset identifier.
    bytes32 asset;
    /// @dev Transfer amount in the asset's native units.
    uint amount;
}
