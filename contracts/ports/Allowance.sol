// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PortBase} from "./Base.sol";
import {AllowanceHook} from "../commands/admin/Allowance.sol";
import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

/// @title RequestAllowancePort
/// @notice Port that lets trusted peers set their own asset allowances.
/// Each ASSET_AMOUNT block is scoped to the authenticated caller and applied through
/// the shared authoritative allowance hook.
abstract contract RequestAllowancePort is PortBase, AllowanceHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = port("portRequestAllowance", Specs.AssetAmount, Specs.Empty, 0);
    }

    /// @notice Set asset allowances for the calling peer.
    /// @param data ASSET_AMOUNT block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portRequestAllowance(bytes calldata data) external onlyPeer returns (bytes memory, uint) {
        return runPort(id, descriptor, data, portRequestAllowanceOne);
    }

    function portRequestAllowanceOne(Execution memory exec) private {
        uint peer = caller();
        (bytes32 asset, uint amount) = exec.unpackAssetAmount();
        allowance(peer, asset, amount);
    }
}
