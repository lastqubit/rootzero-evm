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

/// @notice Quoted asset and liability quantities, independent of live position state.
/// @dev Consumers define quotation semantics. Both quantities are full-width uints; counterparty is separate.
struct Quote {
    /// @dev Identifier for the quoted asset side.
    bytes32 asset;
    /// @dev Quoted asset quantity in the asset's native units.
    uint amount;
    /// @dev Identifier for the quoted liability side.
    bytes32 liability;
    /// @dev Quoted liability quantity in the liability's native units.
    uint debt;
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
