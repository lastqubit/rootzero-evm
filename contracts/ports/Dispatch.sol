// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PortBase} from "./Base.sol";
import {Flags} from "../utils/Flags.sol";
import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that forward funded dispatch payloads.
abstract contract DispatchPayableHook {
    /// @notice Override to dispatch an encoded payload to `portal`.
    /// @param portal Destination portal implementation's host ID. Implementations
    /// may validate or resolve it for their transport.
    /// @param resources Opaque packed chain-specific destination resources, not
    /// plain native value. EVM adapters extract the low 128-bit value lane with
    /// `useResourceValue`; higher bits may encode execution gas or other data.
    /// @param payload Encoded payload ready for the transport layer.
    /// @param funds Execution used for source value available for transport fees
    /// and destination resource funding.
    function dispatchTo(uint portal, uint resources, bytes memory payload, Execution memory funds) internal virtual;
}

/// @title DispatchPayablePort
/// @notice Port endpoint that forwards DISPATCH blocks to a host-defined dispatch hook.
abstract contract DispatchPayablePort is PortBase, DispatchPayableHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = port("portDispatchPayable", Specs.Dispatch, Specs.Empty, Flags.Funded);
    }

    /// @notice Forward peer-supplied dispatches to the host-defined dispatch hook.
    /// @dev Dispatch hooks receive the shared top-level source value
    ///      budget. Any value not spent by the hook is returned as trusted budget
    ///      credit; this does not transfer ETH back to the peer.
    /// @param data DISPATCH block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    /// @return Remaining native budget credit.
    function portDispatchPayable(bytes calldata data) external payable onlyPeer returns (bytes memory, uint) {
        return runPort(data, descriptor, portDispatchPayableOne);
    }

    function portDispatchPayableOne(Execution memory exec) private {
        (uint portal, uint resources, bytes calldata payload) = exec.unpackDispatch();
        dispatchTo(portal, resources, payload, exec);
    }
}
