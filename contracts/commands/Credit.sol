// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {CreditAccountHook} from "../core/Settlement.sol";

using Executions for Execution;

/// @title CreditAccount
/// @notice Command that delivers BALANCE state blocks to an account via a virtual hook.
/// Use for internally recording credits that have already been posted externally.
abstract contract CreditAccount is CommandBase, CreditAccountHook {
    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("creditAccount", Specs.Balance, Specs.Empty, Specs.Empty, 0);
    }

    /// @notice Return the registered CREDIT_ACCOUNT command ID.
    /// @return Registered command node identifier.
    function creditAccountId() internal view returns (uint) {
        return id;
    }

    /// @notice Credit each BALANCE block from the command state to the command account.
    /// @param context Command context carrying the BALANCE state stream.
    /// @return Empty output state.
    /// @return Zero native budget credit.
    function creditAccount(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, creditAccountOne);
    }

    /// @dev Process one BALANCE item for the CreditAccount endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function creditAccountOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        creditAccount(exec.account, asset, amount);
    }
}
