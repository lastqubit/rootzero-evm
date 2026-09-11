// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PortBase} from "./Base.sol";
import {DebitAccountHook} from "../core/Settlement.sol";
import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

/// @title DebitAccountPort
/// @notice Port that lets a trusted peer debit supplied accounts directly.
/// Each ACCOUNT_AMOUNT block calls `debitAccount` for its account.
abstract contract DebitAccountPort is PortBase, DebitAccountHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = port("portDebitAccount", Specs.AccountAmount, Specs.Empty, 0);
    }

    /// @notice Execute the port-debit call.
    /// @param data ACCOUNT_AMOUNT block stream supplied by the trusted peer.
    /// @return Empty response bytes.
    /// @return Zero native budget credit.
    function portDebitAccount(bytes calldata data) external onlyPeer returns (bytes memory, uint) {
        Execution memory exec = openInput(data, descriptor);

        while (exec.more()) {
            (bytes32 account, bytes32 asset, uint amount) = exec.unpackAccountAmount();
            debitAccount(account, asset, amount);
        }
        
        return exec.close();
    }
}
