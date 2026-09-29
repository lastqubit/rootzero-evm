// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandHost, Position} from "../Core.sol";
import {SwapExactIn, SwapExactOut, SwapExactInHook, SwapExactOutHook} from "../Endpoints.sol";
import {Blocks} from "../codec/Blocks.sol";

contract TestSwapCommands is CommandHost, SwapExactIn, SwapExactOut {
    Position private result;
    uint public calls;
    bool public reject;
    error HookRejected();
    event SwapCalled(bool exactIn, bytes32 asset, uint amount, bytes hops);

    constructor(uint commander) CommandHost(commander) {}

    function configure(Position calldata position, bool fail) external {
        result = position;
        reject = fail;
    }

    function swapExactIn(bytes32 liability, uint debt, uint hopsCur)
        internal override returns (Position memory)
    {
        if (reject) revert HookRejected();
        ++calls;
        emit SwapCalled(true, liability, debt, Blocks.toBytes(hopsCur));
        return result;
    }

    function swapExactOut(bytes32 asset, uint amount, uint hopsCur)
        internal override returns (Position memory)
    {
        if (reject) revert HookRejected();
        ++calls;
        emit SwapCalled(false, asset, amount, Blocks.toBytes(hopsCur));
        return result;
    }
}
