// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

// Example 5: Custom Input Blocks
//
// Custom input blocks let a command accept arbitrary command-specific parameters
// alongside standard protocol blocks, without breaking the rootzero wire format.
//
// This example defines a context-local input key for a block that carries a
// fixed `host` ID followed by an
// AMOUNT child block in its tail.

import {CommandBase, Execution, Executions, HostAmount, Sizes, Specs} from "../contracts/Commands.sol";

import {Blocks} from "../contracts/codec/Blocks.sol";

using Executions for Execution;
using Blocks for uint;

abstract contract MyCommand is CommandBase {
    string private constant INPUT = "{ uint host, #amount as amount }";
    uint private immutable inputSpec;
    uint private immutable descriptor;

    constructor() {
        uint32 size = uint32(32 + Sizes.Amount);
        inputSpec = schema(INPUT, 1, size);
        (, descriptor) = command("myCommand", Specs.Empty, inputSpec, Specs.Custody, 0);
    }

    // sendToHost is the virtual hook implementers override to move the asset.
    function sendToHost(uint host, bytes32 asset, uint amount) internal virtual;

    function unpackInput(
        Execution memory exec
    ) private view returns (uint peer, bytes32 asset, uint amount) {
        (uint abs, uint payloadCur) = exec.enter(inputSpec, 32);

        peer = uint(Blocks.read32(abs));
        // The fixed-size outer schema leaves exactly one AMOUNT block.
        (asset, amount,) = payloadCur.unpackAmount();
    }

    function myCommand(
        bytes calldata context
    ) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, myCommandOne);
    }

    function myCommandOne(Execution memory exec) private {
        (uint targetHost, bytes32 asset, uint amount) = unpackInput(exec);

        // Delegate to the implementer to move the asset to the selected host.
        sendToHost(targetHost, asset, amount);

        // Append a CUSTODY block recording that this asset is now held by `targetHost`.
        exec.outputCustody(HostAmount({host: targetHost, asset: asset, amount: amount}));
    }
}
