// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Calls} from "./Calls.sol";
import {HostIntroduction} from "./Host.sol";
import {Nodes} from "../utils/Nodes.sol";

/// @title UpstreamPort
/// @notice Mixin for hosts that depend on a single port of another host.
/// Introduces this host to the port's host at deployment and calls the port with
/// revert-on-failure semantics. The upstream host must still authorize this host as a
/// peer; an introduction is discovery only. Cross-chain delivery into the commander,
/// which must recover instead of revert, belongs in `Portal`.
abstract contract UpstreamPort is HostIntroduction {
    /// @dev Contract address encoded in the upstream port ID.
    address private immutable upstreamTarget;

    /// @dev ABI selector encoded in the upstream port ID.
    bytes4 private immutable upstreamSelector;

    /// @notice Bind this host to `port` and introduce it to the port's host.
    /// @dev Reverts InvalidId unless `port` is a local port ID with a nonzero address.
    /// Skips the introduction when the target is the commander, which `HostIntroduction`
    /// already introduced to, and for hosts bound to another execution address, which
    /// introduce through that address later. Otherwise reverts if the target does not
    /// accept `introduce(uint,uint,string)`.
    /// @param port Local port node ID this host calls.
    /// @param name Discovery hint emitted with the introduction.
    constructor(uint port, string memory name) {
        upstreamSelector = Nodes.portSelector(port);
        upstreamTarget = Nodes.addr(port);
        if (upstreamTarget != commanderAddr && hostAddr() == address(this)) introduceTo(port, name);
    }

    /// @notice Call the upstream port with `data` and no native value.
    /// @dev Reverts `FailedCall` with the upstream's revert data when the call fails.
    /// Reverts without data on malformed returndata, or on nonempty output when `expectEmpty`.
    /// @param data Raw contents of the port's `bytes` argument.
    /// @param expectEmpty Whether the port's output must be empty.
    /// @return out Output bytes returned by the port.
    /// @return credit Native budget credit reported by the port; no ETH is transferred back.
    function callUpstream(bytes memory data, bool expectEmpty) internal returns (bytes memory out, uint credit) {
        return Calls.raw(upstreamSelector, upstreamTarget, 0, data, expectEmpty);
    }

    /// @notice Call the upstream port with `data` and `value` wei.
    /// @dev Reverts `FailedCall` with the upstream's revert data when the call fails.
    /// Reverts without data on malformed returndata, or on nonempty output when `expectEmpty`.
    /// @param value Native value to forward, in wei.
    /// @param data Raw contents of the port's `bytes` argument.
    /// @param expectEmpty Whether the port's output must be empty.
    /// @return out Output bytes returned by the port.
    /// @return credit Native budget credit reported by the port; no ETH is transferred back.
    function callUpstream(uint value, bytes memory data, bool expectEmpty) internal returns (bytes memory out, uint credit) {
        return Calls.raw(upstreamSelector, upstreamTarget, value, data, expectEmpty);
    }
}
