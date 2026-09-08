// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {PortBase} from "./Base.sol";
import {DebitAccountHook, CreditAccountHook} from "../core/Settlement.sol";
import {Sizes, Specs} from "../codec/Specs.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

/// @title ExchangePort
/// @notice Apply peer-supplied debit/credit pairs through the account hooks.
/// @dev Each unnamed local input parent contains two ACCOUNT_AMOUNT blocks: liability debit first,
/// asset credit second. Accounts may differ. Any failure reverts the entire call.
abstract contract ExchangePort is PortBase, DebitAccountHook, CreditAccountHook {
    string private constant INPUT = "#accountAmount as (debit, credit)";
    uint private immutable inputSpec = schema(1, uint32(2 * Sizes.B96), INPUT, "");
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = port("portExchange", inputSpec, Specs.Empty, 0);
    }

    /// @notice Debit then credit each input parent's ACCOUNT_AMOUNT pair.
    /// @dev Entering the exact 208-byte parent payload and consuming two 104-byte
    /// children lands exactly at the next parent, so no additional end check is needed.
    /// Each block is decoded immediately before its account hook is called.
    /// Account validation and zero-amount handling belong to those hooks, matching
    /// the standalone debit and credit ports. Empty batches are accepted.
    /// @param data Local input parents containing debit account/liability/debt then credit account/asset/amount.
    /// @return Empty response bytes.
    function portExchange(bytes calldata data) external onlyPeer returns (bytes memory) {
        Execution memory exec = openInput(data, descriptor);

        while (exec.enterNext(inputSpec)) {
            (bytes32 account, bytes32 asset, uint amount) = exec.unpackAccountAmount();
            debitAccount(account, asset, amount);
            (account, asset, amount) = exec.unpackAccountAmount();
            creditAccount(account, asset, amount);
        }

        return "";
    }
}
