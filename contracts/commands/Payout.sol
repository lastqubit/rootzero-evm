// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs} from "../codec/Logs.sol";

import {Execution, Executions, CommandBase, Specs} from "./Base.sol";
import {Accounts} from "../utils/Accounts.sol";
import {InvalidAccount} from "../utils/Errors.sol";

using Executions for Execution;

/// @title CreatePayout
/// @notice Command that turns BALANCE state into PAYOUT state for matching RECIPIENT inputs.
/// Each BALANCE block is paired with one RECIPIENT block at the same position, which names the
/// recipient's account and its native address on this chain. Value leaving the protocol goes
/// through PAYOUT, which carries the address and which delivering commands such as `withdraw`,
/// `cashout` and `burn` consume. A zero account with a zero address means burn; delivering
/// commands that pay a recipient reject it.
abstract contract CreatePayout is CommandBase {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("createPayout", Specs.Balance, Specs.Recipient, Specs.Payout, Logs.Output);
    }

    /// @notice Convert BALANCE state blocks into PAYOUT blocks for matching RECIPIENT input blocks.
    /// @dev Unless both the account and the address are zero (a burn, output with a zero recipient),
    /// requires the address to be a nonzero EVM address left-padded to 32 bytes whose user account,
    /// `Accounts.toUser(address)`, equals the account, and reverts with `InvalidAccount` otherwise.
    /// This rejects foreign-chain, SVM, admin, host and opaque accounts. Hints callers to record the
    /// OUTPUT stream, the only record of each PAYOUT: delivering commands consume PAYOUT in full and
    /// do not log it again.
    /// @param context Command context carrying BALANCE state and matching RECIPIENT input.
    /// @return PAYOUT blocks, one per BALANCE block, each paid to its RECIPIENT address.
    /// @return Zero native budget credit.
    function createPayout(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, createPayoutOne);
    }

    /// @dev Process one BALANCE / RECIPIENT item for the CreatePayout endpoint.
    /// @param exec Execution containing the account, source cursors, output writer, and native-value budget.
    function createPayoutOne(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackBalance();
        (bytes32 account, bytes32 addr) = exec.unpackRecipient();
        if (account != 0 || addr != 0) {
            if (
                addr == 0 ||
                uint(addr) >> 160 != 0 ||
                Accounts.toUser(address(uint160(uint(addr)))) != account
            ) revert InvalidAccount();
        }
        exec.outputPayout(addr, asset, amount);
    }
}
