// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {QueryBase} from "./Base.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that expose account balance queries.
abstract contract GetBalanceHook {
    /// @notice Resolve one account's balance for one supported asset.
    /// @dev Concrete implementations define how assets are resolved.
    /// @param account Account identifier carried by the query payload.
    /// @param asset Requested asset identifier.
    /// @return amount Current balance in the asset's native units.
    function getBalance(bytes32 account, bytes32 asset) internal view virtual returns (uint amount);
}

/// @title GetBalance
/// @notice Rootzero query that resolves balances for one or more `(account, asset)` tuples.
/// The input is a run of `ACCOUNT_ASSET` form blocks.
/// The response returns one `ACCOUNT_BALANCE` form block per requested position, preserving input order.
abstract contract GetBalance is QueryBase, GetBalanceHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = query("getBalance", Specs.AccountAsset, Specs.AccountBalance);
    }

    /// @notice Resolve balances for a run of requested `(account, asset)` tuples.
    /// @param input Block-stream input consisting of `accountAsset(account, asset)*`.
    /// @return Block-stream response containing one `accountBalance(account, asset, amount)` block per input block.
    function getBalance(bytes calldata input) external view returns (bytes memory) {
        return runQuery(descriptor, input, getBalanceOne);
    }

    function getBalanceOne(Execution memory exec) private view {
        (bytes32 account, bytes32 asset) = exec.unpackAccountAsset();
        uint amount = getBalance(account, asset);
        exec.outputAccountBalance(account, asset, amount);
    }
}
