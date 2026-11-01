// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AccessDenied} from "./Access.sol";
import {sendChainAsset} from "./Cash.sol";
import {Runtime} from "./Runtime.sol";

/// @title Sweep
/// @notice Lets the commander recover native value held by a host, such as what's left from
/// funded steps or failed deliveries.
abstract contract Sweep is Runtime {
    /// @notice Send native value held by this host to its commander.
    /// @dev Callable by the commander, or by the host itself through an admin `executePayable`.
    /// @param amount Amount to send, in wei.
    function sweep(uint amount) external {
        if (msg.sender != commanderAddr && msg.sender != address(this)) revert AccessDenied();
        sendChainAsset(commanderAddr, amount);
    }
}
