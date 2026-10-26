// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AdminBase, Execution, Executions, Flags, Specs} from "./Base.sol";
using Executions for Execution;

/// @title Unauthorize
/// @notice Admin command that removes a list of IDs from the host's trusted set.
/// Each ENTITY block in the input is untrusted. Only callable by the admin account.
abstract contract Unauthorize is AdminBase {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("unauthorize", Specs.Empty, Specs.Entity, Specs.Empty, Flags.Admin);
    }

    /// @notice Return the registered UNAUTHORIZE command ID.
    /// @return Registered command node identifier.
    function unauthorizeId() internal view returns (uint) {
        return id;
    }

    /// @notice Untrust each ENTITY block in the admin input.
    /// @dev The trust hook publishes Trust records for changes.
    /// @param context Admin command context carrying the ENTITY input stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function unauthorize(
        bytes calldata context
    ) external returns (bytes memory, uint) {
        return runAdmin(descriptor, context, unauthorizeOne);
    }

    /// @dev Process one ENTITY item for the Unauthorize endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function unauthorizeOne(Execution memory exec) private {
        setTrust(exec.unpackEntity(), false);
    }
}
