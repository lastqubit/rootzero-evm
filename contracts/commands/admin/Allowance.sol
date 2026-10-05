// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AdminBase, Execution, Executions, Flags, Specs} from "./Base.sol";
import {Codes} from "../../utils/Codes.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that configure peer asset allowances.
abstract contract AllowanceHook {
    /// @notice Apply or revoke one host-scoped allowance.
    /// @dev Called once per ALLOWANCE block in the input. Implementations decide
    /// how the allowance is represented, e.g. ERC-20 approval, an internal cap,
    /// or another host-specific authorization record.
    /// @param peer Host node receiving the allowed cap.
    /// @param asset Asset identifier.
    /// @param amount Allowed cap amount. A zero amount MUST revoke the allowance.
    function allowance(uint peer, bytes32 asset, uint amount) internal virtual;
}

/// @title Allowance
/// @notice Admin command that applies cross-host allowance entries via a virtual hook.
/// Each ALLOWANCE block grants or updates a host-scoped asset cap. Only callable by the admin account.
abstract contract Allowance is AdminBase, AllowanceHook {
    uint private constant INPUT = Specs.Allowance | Codes.HostUpdate;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("allowance", Specs.Empty, INPUT, Specs.Empty, Flags.Admin);
    }

    /// @notice Apply each ALLOWANCE block in the admin input.
    /// @dev Logs the complete host-scoped INPUT batch before hooks.
    /// @param context Admin command context carrying the ALLOWANCE input stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function allowance(
        bytes calldata context
    ) external returns (bytes memory, uint) {
        return runAdmin(id, descriptor, context, allowanceOne);
    }

    function allowanceOne(Execution memory exec) private {
        (uint peer, bytes32 asset, uint amount) = exec.unpackAllowance();
        allowance(peer, asset, amount);
    }
}
