// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

// Import shims ensure every custom-command example builds and can be exercised
// through the public Commands.sol authoring barrel.
import {Host} from "../Core.sol";
import {ExampleHost as MinimalHostExample} from "../../examples/1-Host.sol";
import {MyCommand as BasicCommandExample} from "../../examples/3-Command.sol";
import {MyCommand as BatchCommandExample} from "../../examples/4-Batch.sol";
import {MyCommand as DataCommandExample} from "../../examples/5-Data.sol";
import {ExampleHost as ListExampleHost} from "../../examples/6-List.sol";
import {ExampleHost as SwapExampleHost} from "../../examples/9-Swap.sol";

/// @notice Concrete wrapper ensuring the minimal command-host example compiles.
contract TestMinimalHostExample is MinimalHostExample {
    constructor(uint commander) MinimalHostExample(commander) {}
}

/// @notice Concrete host used to exercise the single-input command example.
contract TestBasicCommandExampleHost is Host, BasicCommandExample {
    constructor(uint rootzero) Host(rootzero, "TestCommandExamplesImport", address(0)) {}
}

/// @notice Concrete host used to exercise the batch command example.
contract TestBatchCommandExampleHost is Host, BatchCommandExample {
    constructor(uint rootzero) Host(rootzero, "TestCommandExamplesImport", address(0)) {}
}

/// @notice Concrete host used to exercise the custom-data command example.
contract TestDataCommandExampleHost is Host, DataCommandExample {
    event SentToHost(uint host, bytes32 asset, uint amount);

    constructor(uint rootzero) Host(rootzero, "TestCommandExamplesImport", address(0)) {}

    function sendToHost(uint host, bytes32 asset, uint amount) internal override {
        emit SentToHost(host, asset, amount);
    }
}

/// @notice Concrete wrapper ensuring the custom-keyed list example compiles.
contract TestListCommandExampleHost is ListExampleHost {
    constructor(uint rootzero) ListExampleHost(rootzero) {}
}

/// @notice Concrete wrapper ensuring the nested swap example compiles.
contract TestSwapExampleHost is SwapExampleHost {
    constructor(uint rootzero) SwapExampleHost(rootzero) {}
}
