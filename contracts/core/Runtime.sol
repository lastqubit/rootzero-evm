// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Assets} from "../utils/Assets.sol";
import {Accounts} from "../utils/Accounts.sol";
import {Nodes} from "../utils/Nodes.sol";

/// @title ChainAsset
/// @notice Shared chain asset identity for host helpers.
abstract contract ChainAsset {
    /// @dev Asset ID for the chain coin/token, bound to the current chain at deployment.
    bytes32 internal immutable chainAsset = Assets.toChain();
}

/// @title Runtime
/// @notice Shared runtime for host and chain asset identities.
abstract contract Runtime is ChainAsset {
    /// @dev This contract's host node ID, derived from `self` at construction.
    uint public immutable host;

    /// @dev Commander host ID. Defaults to this contract's host ID when self-managed.
    uint internal immutable commander;

    /// @dev Native address embedded in `commander`, resolved once at construction.
    address internal immutable commanderAddr;

    /// @param cmdr Local host ID of the commander, or zero to make this runtime self-managed.
    /// @param self Execution address, or zero to use this deployment's address.
    constructor(uint cmdr, address self) {
        if (self == address(0)) self = address(this);
        host = Nodes.toHost(self);
        commander = cmdr == 0 ? host : cmdr;
        commanderAddr = Nodes.hostAddr(commander);
    }

    /// @notice Execution address embedded in this runtime's host node.
    function hostAddr() public view returns (address) {
        return address(uint160(host));
    }

    /// @notice This runtime's host account, preserving the host node's chain and address.
    function hostAccount() public view returns (bytes32) {
        return Accounts.toHost(host);
    }
}
