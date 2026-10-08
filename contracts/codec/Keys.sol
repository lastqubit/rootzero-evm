// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

/// @dev Right-aligned Keys.List for direct assembly use: bytes4(keccak256("#list")).
uint constant LIST_KEY = 0x8454537f;

/// @dev Right-aligned Keys.Bytes for direct assembly use: bytes4(keccak256("#bytes")).
uint constant BYTES_KEY = 0x6911b332;

/// @dev Right-aligned Keys.State for direct assembly use: bytes4(keccak256("#state")).
uint constant STATE_KEY = 0xe31b08ab;

/// @dev Right-aligned Keys.Input for direct assembly use: bytes4(keccak256("#input")).
uint constant INPUT_KEY = 0x6b2ede62;

/// @dev Right-aligned Keys.AccountBalance for direct assembly use: bytes4(keccak256("#accountBalance")).
uint constant ACCOUNT_BALANCE_KEY = 0x2da7f737;

/// @dev Right-aligned Keys.Bootstrap for direct assembly use: bytes4(keccak256("#bootstrap")).
uint constant BOOTSTRAP_KEY = 0x440f90da;

/// @dev Right-aligned Keys.Step for direct assembly use: bytes4(keccak256("#step")).
uint constant STEP_KEY = 0x53a8ad94;

/// @dev Right-aligned Keys.Context for direct assembly use: bytes4(keccak256("#context")).
uint constant CONTEXT_KEY = 0xc5769e23;

/// @dev Right-aligned Keys.Relay for direct assembly use: bytes4(keccak256("#relay")).
uint constant RELAY_KEY = 0xc34cc52a;

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

    /// @dev Context state container; payload is a block stream.
    bytes4 constant State = bytes4(keccak256("#state"));
    /// @dev Context input container; payload is a block stream.
    bytes4 constant Input = bytes4(keccak256("#input"));
    /// @dev Event-only container for an execution output stream.
    bytes4 constant Output = bytes4(keccak256("#output"));

    // Live pipeline state

    /// @dev Asset balance state - (bytes32 asset, uint amount)
    bytes4 constant Balance = bytes4(keccak256("#balance"));
    /// @dev Cross-host custody state - (uint host, bytes32 asset, uint amount)
    bytes4 constant Custody = bytes4(keccak256("#custody"));
    /// @dev Asset-liability position state - (bytes32 asset, uint amount, bytes32 liability, uint debt, bytes32 counterparty)
    bytes4 constant Position = bytes4(keccak256("#position"));
    /// @dev Account debit/credit booking - (bytes32 from, bytes32 to, bytes32 liability, uint debt, bytes32 asset, uint amount).
    bytes4 constant Booking = bytes4(keccak256("#booking"));

    // Input and value blocks

    /// @dev Packed bounds: high 128 bits inclusive minimum, low 128 bits inclusive maximum; context defines meaning.
    bytes4 constant Limits = bytes4(keccak256("#limits"));
    /// @dev Exact asset and full-width inclusive minimum/maximum amount.
    bytes4 constant BalanceConstraints = bytes4(keccak256("#balanceConstraints"));
    /// @dev Exact asset/liability identifiers and inclusive minimum amount / maximum debt bounds.
    bytes4 constant PositionConstraints = bytes4(keccak256("#positionConstraints"));
    /// @dev Quoted asset and liability quantities; interpretation belongs to the consumer.
    bytes4 constant Quote = bytes4(keccak256("#quote"));

    /// @dev Scalar input amount; the consumer defines its unit - (uint amount)
    bytes4 constant Amount = bytes4(keccak256("#amount"));
    /// @dev Asset input amount - (bytes32 asset, uint amount)
    bytes4 constant AssetAmount = bytes4(keccak256("#assetAmount"));
    /// @dev Pipeline bootstrap request - minimum budget and LIST of ASSET_AMOUNT blocks.
    bytes4 constant Bootstrap = bytes4(keccak256("#bootstrap"));
    /// @dev Host-scoped input amount - (uint host, bytes32 asset, uint amount)
    bytes4 constant Allocation = bytes4(keccak256("#allocation"));
    /// @dev Host-scoped allowance cap - (uint host, bytes32 asset, uint amount)
    bytes4 constant Allowance = bytes4(keccak256("#allowance"));
    /// @dev Account identifier - (bytes32 account)
    bytes4 constant Account = bytes4(keccak256("#account"));
    /// @dev Transfer record passed through the pipeline - (bytes32 from, bytes32 to, bytes32 asset, uint amount)
    bytes4 constant Transaction = bytes4(keccak256("#transaction"));

    /// @dev Pipeline context - (bytes32 account, uint budget).
    bytes4 constant Pipeline = bytes4(keccak256("#pipeline"));

    // Composite and annotation blocks

    /// @dev Swap route - (bytes32 asset, uint amount, many #asset as hops)
    bytes4 constant Swap = bytes4(keccak256("#swap"));
    /// @dev Sub-command invocation - (uint cmd, uint value, #input)
    bytes4 constant Step = bytes4(keccak256("#step"));
    /// @dev Pipeline handoff envelope - (#input, #bytes as steps)
    bytes4 constant Relay = bytes4(keccak256("#relay"));
    /// @dev Command context transport - (bytes32 account, #state, #input)
    bytes4 constant Context = bytes4(keccak256("#context"));
    /// @dev Recoverable witness - (uint handler, uint value, bytes32 key, #bytes as witness)
    bytes4 constant Recover = bytes4(keccak256("#recover"));
    /// @dev Portal encoded payload dispatch - (uint portal, uint resources, #bytes as payload)
    bytes4 constant Dispatch = bytes4(keccak256("#dispatch"));
    /// @dev Raw external call - (uint target, uint value, #bytes as payload)
    bytes4 constant Call = bytes4(keccak256("#call"));
    /// @dev Asset descriptor without amount - (bytes32 asset)
    bytes4 constant Asset = bytes4(keccak256("#asset"));
    /// @dev Asset preimage publication - (bytes32 asset, #bytes as preimage)
    bytes4 constant AssetPreimage = bytes4(keccak256("#assetPreimage"));
    /// @dev Node identifier - (uint id)
    bytes4 constant Node = bytes4(keccak256("#node"));
    /// @dev Generic entity identifier - (uint entity)
    bytes4 constant Entity = bytes4(keccak256("#entity"));
    /// @dev Transport envelope - (uint portal, uint resources, bytes32 key, bytes32 digest)
    bytes4 constant Envelope = bytes4(keccak256("#envelope"));
    /// @dev Recovery record - (bytes32 key, bytes32 digest)
    bytes4 constant Resolution = bytes4(keccak256("#resolution"));
    /// @dev Host introduction claim - (uint peer, bytes32 origin, uint blocknum)
    bytes4 constant Introduction = bytes4(keccak256("#introduction"));
    /// @dev Endpoint data block - (uint id, uint state, uint input, uint output)
    bytes4 constant Endpoint = bytes4(keccak256("#endpoint"));
    /// @dev Entity counterparty annotation - (bytes32 account)
    bytes4 constant Counterparty = bytes4(keccak256("#counterparty"));
    /// @dev Command loop-group annotation - (#string as description)
    bytes4 constant Groups = bytes4(keccak256("#groups"));
    /// @dev Block schema publication - (uint spec, #string as body)
    bytes4 constant Schema = bytes4(keccak256("#schema"));

    /// @dev Structural status form - (uint code)
    bytes4 constant Status = bytes4(keccak256("#status"));
    /// @dev Structural asset-liability pair - (bytes32 asset, bytes32 liability)
    bytes4 constant AssetLiability = bytes4(keccak256("#assetLiability"));
    /// @dev Structural account asset form - (bytes32 account, bytes32 asset)
    bytes4 constant AccountAsset = bytes4(keccak256("#accountAsset"));
    /// @dev Structural host asset form - (uint host, bytes32 asset)
    bytes4 constant HostAsset = bytes4(keccak256("#hostAsset"));
    /// @dev Actual account balance - (bytes32 account, bytes32 asset, uint amount).
    bytes4 constant AccountBalance = bytes4(keccak256("#accountBalance"));
    /// @dev Structural account amount form - (bytes32 account, bytes32 asset, uint amount)
    bytes4 constant AccountAmount = bytes4(keccak256("#accountAmount"));
    /// @dev Structural host amount form - (uint host, bytes32 asset, uint amount)
    bytes4 constant HostAmount = bytes4(keccak256("#hostAmount"));
    /// @dev Structural host account asset form - (uint host, bytes32 account, bytes32 asset)
    bytes4 constant HostAccountAsset = bytes4(keccak256("#hostAccountAsset"));
    /// @dev Structural host account amount form - (uint host, bytes32 account, bytes32 asset, uint amount)
    bytes4 constant HostAccountAmount = bytes4(keccak256("#hostAccountAmount"));
}
