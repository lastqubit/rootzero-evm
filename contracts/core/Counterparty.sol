// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Accounts} from "../utils/Accounts.sol";

/// @title Counterparty
/// @notice Shared immutable counterparty configuration for inheriting contracts.
abstract contract Counterparty {
    /// @notice Account used as the settlement counterparty.
    bytes32 internal immutable counterparty;

    /// @notice Set the counterparty for the lifetime of the deployed contract.
    /// @dev Validates the account category; rejects zero with InvalidAccount.
    /// @param account Settlement counterparty account identifier.
    constructor(bytes32 account) {
        counterparty = Accounts.account(account);
    }
}
