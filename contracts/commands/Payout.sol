// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Accounts} from "../utils/Accounts.sol";

using Executions for Execution;

/// @title CreatePayout
/// @notice Command that turns BALANCE state into PAYOUT state for matching ACCOUNT input recipients.
/// Each BALANCE block is paired with one ACCOUNT block at the same position. Value leaving the
/// protocol goes through PAYOUT, which delivering commands such as `withdraw`, `cashout` and
/// `burn` consume. A zero recipient means burn; delivering commands that pay a recipient reject it.
abstract contract CreatePayout is CommandBase {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("createPayout", Specs.Balance, Specs.Account, Specs.Payout, Logs.Output);
    }

    /// @notice Convert BALANCE state blocks into PAYOUT blocks for matching ACCOUNT input blocks.
    /// @dev Validates nonzero recipient account categories; a zero recipient passes unchanged.
    /// Hints callers to record the OUTPUT stream, the only record of each PAYOUT: delivering
    /// commands consume PAYOUT in full and do not log it again.
    /// @param context Command context carrying BALANCE state and matching ACCOUNT input.
    /// @return PAYOUT blocks, one per BALANCE block.
    /// @return Zero native budget credit.
    function createPayout(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, createPayoutOne);
    }

    /// @dev Process one BALANCE / ACCOUNT item for the CreatePayout endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function createPayoutOne(Execution memory exec) private {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        bytes32 recipient = exec.unpackAccount();
        if (recipient != 0) Accounts.account(recipient);
        exec.outputPayout(recipient, asset, amount);
    }
}
