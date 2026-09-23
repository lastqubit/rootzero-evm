// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host} from "../core/Host.sol";
import {CommandBase, Execution, Executions, Specs} from "../commands/Base.sol";
import {BurnHook} from "../commands/Burn.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";

/// @dev Frozen pre-run Burn implementation for comparison with TestBurnHost.
abstract contract BurnLoopBaseline is CommandBase, BurnHook, ActionAnnot {
    using Executions for Execution;
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("burn", Specs.Balance, Specs.Empty, Specs.Empty, 0);
        annotateAction(id, Actions.Burn);
    }

    function burn(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, descriptor);
        while (exec.more()) {
            (bytes32 asset, uint amount) = exec.unpackBalance();
            burn(exec.account, asset, amount);
        }
        return exec.close();
    }
}

/// @dev Same host, access setup, event hook, and external ABI as TestBurnHost.
contract TestBurnLoopHost is Host, BurnLoopBaseline {
    event BurnCalled(bytes32 account, bytes32 asset, uint amount);

    constructor(uint cmdr) Host(0) BurnLoopBaseline() {
        if (cmdr != 0) authorizeNode(cmdr);
    }

    function burn(bytes32 account, bytes32 asset, uint amount) internal override returns (uint) {
        emit BurnCalled(account, asset, amount);
        return amount;
    }

    function getAdminAccount() external view returns (bytes32) { return admin; }
}
