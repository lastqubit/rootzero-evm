// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandHost, Counterparty} from "../Core.sol";
import {SwapExactInput, SwapExactOutput, SwapAssetExactInput, SwapDebtExactOutput} from "../Endpoints.sol";

contract TestSwapCommands is CommandHost, SwapExactInput, SwapExactOutput, SwapAssetExactInput, SwapDebtExactOutput {
    uint public calls;
    uint private adjustment;
    uint private rejectAt;
    error HookRejected();
    event SwapCalled(bool exactInput, bytes32 asset, uint amount, bytes32 next);

    constructor(uint commander, bytes32 account) CommandHost(commander, "TestSwapCommands") Counterparty(account) {}

    function configure(uint delta, uint failAt) external {
        adjustment = delta;
        rejectAt = failAt;
    }

    function swapExactInput(bytes32 liability, uint debt, bytes32 asset)
        internal override returns (uint amount)
    {
        if (++calls == rejectAt) revert HookRejected();
        emit SwapCalled(true, liability, debt, asset);
        return debt - adjustment;
    }

    function swapExactOutput(bytes32 asset, uint amount, bytes32 liability)
        internal override returns (uint debt)
    {
        if (++calls == rejectAt) revert HookRejected();
        emit SwapCalled(false, asset, amount, liability);
        return amount + adjustment;
    }
}
