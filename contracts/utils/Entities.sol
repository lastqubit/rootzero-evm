// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @notice Canonical entity-kind identifiers describing the associated subject.
/// @dev Codes fields pack up to eight uint32 IDs into a uint, lowest slot first.
/// Entities occupy category 1 (0x20000000-0x3fffffff) of eight possible categories.
/// Constants include the top three category bits and can be passed directly as codes.
/// These identifiers are not bit flags or full-width entity identities.
/// Kind information is optional when already established by the event or subject ID.
/// Zero denotes an empty list or unused high slots; there is no Entities.None.
/// @dev Constants use uint for composition; each identifier must still fit one uint32 slot.
library Entities {
    /// @dev An asset.
    uint constant Asset = 0x20000000;
    /// @dev An account.
    uint constant Account = 0x20000001;
    /// @dev A host.
    uint constant Host = 0x20000002;
    /// @dev A command.
    uint constant Command = 0x20000003;
    /// @dev A query.
    uint constant Query = 0x20000004;
    /// @dev A route.
    uint constant Route = 0x20000005;
    /// @dev An asset-liability position.
    uint constant Position = 0x20000006;
    /// @dev A guardian.
    uint constant Guardian = 0x20000007;
    /// @dev A pool.
    uint constant Pool = 0x20000008;
    /// @dev A port.
    uint constant Port = 0x20000009;
    /// @dev A balance.
    uint constant Balance = 0x2000000a;

    // Values 0x2000000b-0x3fffffff are reserved for future entity kinds.
}
