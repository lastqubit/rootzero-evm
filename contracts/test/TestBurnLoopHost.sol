// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host} from "../core/Host.sol";
import {CommandBase, Execution, Executions, Specs} from "../commands/Base.sol";
import {BurnHook} from "../commands/Burn.sol";
import {Codes} from "../utils/Codes.sol";

/// @dev Pre-run Burn loop with current lane logging, for comparison with TestBurnHost.
abstract contract BurnLoopBaseline is CommandBase, BurnHook {
    using Executions for Execution;
    uint private constant STATE = Specs.Balance | Codes.AccountBurn;

    uint private immutable descriptor;
    uint private immutable id;

    constructor() {
        (id, descriptor) = command("burn", STATE, Specs.Empty, Specs.Empty, 0);
    }

    function burn(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        Execution memory exec = openCommand(context, descriptor);
        exec.logContext(id, descriptor);
        while (exec.more()) {
            (bytes32 asset, uint amount) = exec.unpackBalance();
            burn(exec.account, asset, amount);
        }
        return exec.close(id, descriptor);
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
