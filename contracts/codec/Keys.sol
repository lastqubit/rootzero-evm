// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @title Keys
/// @notice Standard block type selectors for the rootzero block stream protocol.
/// Standard keys use the first 4 bytes of `keccak256("#name")` by convention.
/// Custom block keys only need to be unique in the context where they are used;
/// hosts may publish custom key meanings with `#schema` annotations.
library Keys {
    // Empty and reserved blocks

    /// @dev Empty / unset key.
    bytes4 constant Empty = bytes4(0);
    /// @dev List wrapper; payload is an embedded repeated block stream.
    bytes4 constant List = bytes4(keccak256("#list"));
    /// @dev Reserved raw bytes child block.
    bytes4 constant Bytes = bytes4(keccak256("#bytes"));
    /// @dev Reserved UTF-8 string child block.
    bytes4 constant String = bytes4(keccak256("#string"));

    // Live pipeline state

    /// @dev Asset balance state - (bytes32 asset, uint amount)
    bytes4 constant Balance = bytes4(keccak256("#balance"));
    /// @dev Cross-host custody state - (uint host, bytes32 asset, uint amount)
    bytes4 constant Custody = bytes4(keccak256("#custody"));
    /// @dev Asset-liability position state - (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty)
    bytes4 constant Position = bytes4(keccak256("#position"));

    // Input and value blocks

    /// @dev Packed quantity bounds - (uint limits): high 128 bits minimum amount, low 128 bits maximum debt.
    bytes4 constant Limits = bytes4(keccak256("#limits"));
    /// @dev Expected position outcome - (bytes32 asset, bytes32 liability, bytes32 counterparty, uint limits)
    bytes4 constant Quote = bytes4(keccak256("#quote"));

    /// @dev Input amount - (bytes32 asset, uint amount)
    bytes4 constant Amount = bytes4(keccak256("#amount"));
    /// @dev Pipeline bootstrap request - (bytes32 asset, uint amount, uint budget)
    bytes4 constant Bootstrap = bytes4(keccak256("#bootstrap"));
    /// @dev Host-scoped input amount - (uint host, bytes32 asset, uint amount)
    bytes4 constant Allocation = bytes4(keccak256("#allocation"));
    /// @dev Host-scoped allowance cap - (uint host, bytes32 asset, uint amount)
    bytes4 constant Allowance = bytes4(keccak256("#allowance"));
    /// @dev Account identifier - (bytes32 account)
    bytes4 constant Account = bytes4(keccak256("#account"));
    /// @dev Transfer record passed through the pipeline - (bytes32 from, bytes32 to, bytes32 asset, uint amount)
    bytes4 constant Transaction = bytes4(keccak256("#transaction"));

    // Composite and annotation blocks

    /// @dev Sub-command invocation - (uint cmd, uint value, #bytes as input)
    bytes4 constant Step = bytes4(keccak256("#step"));
    /// @dev Pipeline handoff envelope - (#bytes as input, #bytes as steps)
    bytes4 constant Relay = bytes4(keccak256("#relay"));
    /// @dev Command context transport - (bytes32 account, #bytes as state, #bytes as input)
    bytes4 constant Context = bytes4(keccak256("#context"));
    /// @dev Recoverable witness - (uint handler, uint resources, bytes32 key, #bytes as witness)
    bytes4 constant Recover = bytes4(keccak256("#recover"));
    /// @dev Portal encoded payload dispatch - (uint portal, uint resources, #bytes as payload)
    bytes4 constant Dispatch = bytes4(keccak256("#dispatch"));
    /// @dev Raw external call - (uint target, uint resources, #bytes as payload)
    bytes4 constant Call = bytes4(keccak256("#call"));
    /// @dev Asset descriptor without amount - (bytes32 asset)
    bytes4 constant Asset = bytes4(keccak256("#asset"));
    /// @dev Node identifier - (uint id)
    bytes4 constant Node = bytes4(keccak256("#node"));
    /// @dev Entity label annotation - (bytes32 namespace, #string as name)
    bytes4 constant Label = bytes4(keccak256("#label"));
    /// @dev Entity annotations - (uint entity, #bytes as data)
    bytes4 constant Annotation = bytes4(keccak256("#annotation"));
    /// @dev Primary semantic action annotation - (uint action)
    bytes4 constant Action = bytes4(keccak256("#action"));
    /// @dev Entity counterparty annotation - (bytes32 account)
    bytes4 constant Counterparty = bytes4(keccak256("#counterparty"));
    /// @dev Block schema publication - (bytes4 key, #string as body, bytes32 name)
    bytes4 constant Schema = bytes4(keccak256("#schema"));

    /// @dev Structural status form - (uint code)
    bytes4 constant Status = bytes4(keccak256("#status"));
    /// @dev Structural asset-liability pair - (bytes32 asset, bytes32 liability)
    bytes4 constant AssetLiability = bytes4(keccak256("#assetLiability"));
    /// @dev Structural account asset form - (bytes32 account, bytes32 asset)
    bytes4 constant AccountAsset = bytes4(keccak256("#accountAsset"));
    /// @dev Structural host asset form - (uint host, bytes32 asset)
    bytes4 constant HostAsset = bytes4(keccak256("#hostAsset"));
    /// @dev Structural account amount form - (bytes32 account, bytes32 asset, uint amount)
    bytes4 constant AccountAmount = bytes4(keccak256("#accountAmount"));
    /// @dev Structural host amount form - (uint host, bytes32 asset, uint amount)
    bytes4 constant HostAmount = bytes4(keccak256("#hostAmount"));
    /// @dev Structural host account asset form - (uint host, bytes32 account, bytes32 asset)
    bytes4 constant HostAccountAsset = bytes4(keccak256("#hostAccountAsset"));
    /// @dev Structural host account amount form - (uint host, bytes32 account, bytes32 asset, uint amount)
    bytes4 constant HostAccountAmount = bytes4(keccak256("#hostAccountAmount"));
}
