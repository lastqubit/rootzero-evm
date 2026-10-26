// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {PortBase} from "./Base.sol";
import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

/// @title RequestAssetHook
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

/// @title RequestAssetPort
/// @notice Port that lets trusted peers request assets from the receiving host.
/// Each ASSET_AMOUNT block is scoped to the caller and passed unchanged to
/// `requestAsset(peer, asset, amount)`. The hook validates support and performs
/// any accounting and transfer required by the host.
abstract contract RequestAssetPort is PortBase, RequestAssetHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = port("portRequestAsset", Specs.AssetAmount, Specs.Empty, 0);
    }

    /// @notice Request assets for the calling peer.
    /// @param data ASSET_AMOUNT block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portRequestAsset(bytes calldata data) external onlyPeer returns (bytes memory, uint) {
        return runPort(descriptor, data, portRequestAssetOne);
    }

    /// @dev Process one ASSET_AMOUNT item for the RequestAssetPort endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function portRequestAssetOne(Execution memory exec) private {
        uint peer = caller();
        (bytes32 asset, uint amount) = exec.unpackAssetAmount();
        requestAsset(peer, asset, amount);
    }
}
