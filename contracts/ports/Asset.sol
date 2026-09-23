// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PortBase} from "./Base.sol";
import {AllowAssetHook, DenyAssetHook} from "../commands/admin/Asset.sol";
import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that fulfill asset requests from peers.
abstract contract RequestAssetHook {
    /// @notice Override to handle one asset request from a peer host.
    /// @dev The implementation is responsible for validating `asset`, enforcing
    /// requester policy, and sending the approved amount to the requester.
    /// @param peer Peer host node ID for this request.
    /// @param asset Asset identifier supplied by the peer.
    /// @param amount Amount requested in the asset's native units.
    function requestAsset(uint peer, bytes32 asset, uint amount) internal virtual;
}

/// @title AllowAssetPort
/// @notice Port that permits a list of assets on behalf of a peer host.
/// Each ASSET block in the input calls `allowAsset`. Restricted to trusted peers.
abstract contract AllowAssetPort is PortBase, AllowAssetHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = port("portAllowAsset", Specs.Asset, Specs.Empty, 0);
    }

    /// @notice Execute the allow-asset peer call.
    /// @param data ASSET block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portAllowAsset(bytes calldata data) external onlyPeer returns (bytes memory, uint) {
        return runPort(data, descriptor, portAllowAssetOne);
    }

    function portAllowAssetOne(Execution memory exec) private {
        bytes32 asset = exec.unpackAsset();
        allowAsset(asset);
    }
}

/// @title DenyAssetPort
/// @notice Port that blocks a list of assets on behalf of a peer host.
/// Each ASSET block in the input calls `denyAsset`. Restricted to trusted peers.
abstract contract DenyAssetPort is PortBase, DenyAssetHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = port("portDenyAsset", Specs.Asset, Specs.Empty, 0);
    }

    /// @notice Execute the deny-asset peer call.
    /// @param data ASSET block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portDenyAsset(bytes calldata data) external onlyPeer returns (bytes memory, uint) {
        return runPort(data, descriptor, portDenyAssetOne);
    }

    function portDenyAssetOne(Execution memory exec) private {
        bytes32 asset = exec.unpackAsset();
        denyAsset(asset);
    }
}

/// @title RequestAssetPort
/// @notice Port that lets trusted peers request assets from the receiving host.
/// Each AMOUNT block is scoped to the caller and passed unchanged to
/// `requestAsset(peer, asset, amount)`. The hook validates support and performs
/// any accounting and transfer required by the host.
abstract contract RequestAssetPort is PortBase, RequestAssetHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = port("portRequestAsset", Specs.Amount, Specs.Empty, 0);
    }

    /// @notice Request assets for the calling peer.
    /// @param data AMOUNT block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portRequestAsset(bytes calldata data) external onlyPeer returns (bytes memory, uint) {
        return runPort(data, descriptor, portRequestAssetOne);
    }

    function portRequestAssetOne(Execution memory exec) private {
        uint peer = caller();
        (bytes32 asset, uint amount) = exec.unpackAmount();
        requestAsset(peer, asset, amount);
    }
}
