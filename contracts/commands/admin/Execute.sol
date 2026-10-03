// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AdminBase, Execution, Executions, Flags, Specs} from "./Base.sol";
import {FailedCall} from "../../core/Calls.sol";
import {Nodes} from "../../utils/Nodes.sol";

using Executions for Execution;

/// @title ExecutePayable
/// @notice Admin command that forwards raw calldata to one or more target nodes.
/// Each CALL block specifies a target node ID, full-width native value, and raw
/// calldata payload. The shared execution budget funds each call.
/// Only callable by the admin account.
/// Unspent top-level `msg.value` is returned as native budget credit.
abstract contract ExecutePayable is AdminBase {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("executePayable", Specs.Empty, Specs.Call, Specs.Empty, Flags.AdminFunded);
    }

    /// @dev Execute arbitrary calldata while ignoring successful returndata.
    /// Returndata is copied only when needed to report a failed call.
    function callTarget(uint target, uint value, uint dataCur) private {
        address addr = Nodes.addr(target);
        bytes4 selector;
        bool success;
        bytes memory err;

        assembly ("memory-safe") {
            let scratch := mload(0x40)
            let abs := and(dataCur, 0xffffffff)
            let len := sub(and(shr(32, dataCur), 0xffffffff), abs)
            calldatacopy(scratch, abs, len)
            success := call(gas(), addr, value, scratch, len, 0, 0)

            if iszero(success) {
                selector := mload(scratch)
                // Match bytes4 conversion: short input is right-padded with zeros.
                if lt(len, 4) {
                    let shift := sub(256, mul(len, 8))
                    selector := shl(shift, shr(shift, selector))
                }
                let size := returndatasize()
                err := scratch
                mstore(err, size)
                returndatacopy(add(err, 0x20), 0, size)
                mstore(add(add(err, 0x20), size), 0)
                mstore(0x40, and(add(add(add(err, 0x20), size), 0x1f), not(0x1f)))
            }
        }

        if (!success) revert FailedCall(addr, selector, err);
    }

    /// @notice Execute each CALL block in the admin input.
    /// @param context Admin command context carrying the CALL input stream.
    /// @return Empty output state.
    /// @return Native value to add to the caller's budget.
    function executePayable(
        bytes calldata context
    ) external payable returns (bytes memory, uint) {
        return runAdmin(id, descriptor, context, executePayableOne);
    }

    function executePayableOne(Execution memory exec) private {
        (uint target, uint value, uint dataCur) = exec.unpackCall();
        callTarget(target, exec.useValue(value), dataCur);
    }
}
