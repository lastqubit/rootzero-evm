// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host} from "../core/Host.sol";
import {Logs} from "../codec/Logs.sol";
import {CommandBase, Execution, Executions, Specs} from "../commands/Base.sol";

using Executions for Execution;

/// @dev Test-only command hinting State and Input, so pipeline record tests cover both
/// hints with a real external step. Consumes BALANCE state paired with ACCOUNT input.
abstract contract Hinted is CommandBase {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = command("hinted", Specs.Balance, Specs.Account, Specs.Empty, Logs.State | Logs.Input);
    }

    function hinted(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(descriptor, context, hintedOne);
    }

    function hintedOne(Execution memory exec) private pure {
        exec.unpackBalance();
        exec.unpackAccount();
    }
}

contract TestHintedHost is Host, Hinted {
    constructor(uint cmdr) Host(0, "TestHintedHost", address(0)) {
        if (cmdr != 0) setTrust(cmdr, true);
    }
}
