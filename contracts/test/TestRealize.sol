// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Accounts} from "../utils/Accounts.sol";

import {Realize} from "../commands/Realize.sol";
import {Position} from "../core/Types.sol";
import {UnexpectedValue} from "../utils/Errors.sol";
import {Runtime} from "../core/Runtime.sol";

/// @dev Stateful hooks let tests observe transaction rollback and failure order.
contract TestRealize is Realize {
    error AssetFailure(uint assetCalls, uint debtCalls);
    error DebtFailure(uint assetCalls, uint debtCalls);

    uint public assetCalls;
    uint public debtCalls;
    uint public realizedAssets;
    uint public realizedDebts;
    uint private failAssetAt;
    uint private failDebtAt;

    constructor() Runtime(0) {}

    function failAt(uint assetCall, uint debtCall) external {
        failAssetAt = assetCall;
        failDebtAt = debtCall;
    }

    function enforceCaller(address caller) internal pure override returns (address) {
        return caller;
    }

    function realize(bytes32 account, Position memory position) internal override returns (Position memory) {
        if (position.counterparty != Accounts.toHost(host)) revert UnexpectedValue();
        // This host chooses debt first; the command does not prescribe the order.
        ++debtCalls;
        realizedDebts += position.debt;
        if (debtCalls == failDebtAt) revert DebtFailure(assetCalls, debtCalls);
        ++assetCalls;
        realizedAssets += position.amount;
        if (assetCalls == failAssetAt) revert AssetFailure(assetCalls, debtCalls);
        position.counterparty = bytes32(0);
        return position;
    }
}
