// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

// Example 7: Custom Input Shape
//
// Discoverable custom input types define a context-local spec with a small
// literal or selector as its key, then publish it with a #schema annotation.
//
// For:
//
//   { bytes32 asset, uint amount, #status }
//
// the encoded input item is:
//
//   PAYMENT(asset | amount | STATUS(status))
//
// A zero status is encoded as a regular STATUS(0) value.

import {Host} from "../contracts/Core.sol";
import {CommandBase, Execution, Executions, Sizes, Specs} from "../contracts/Commands.sol";

import {Blocks} from "../contracts/codec/Blocks.sol";

using Executions for Execution;
using Blocks for uint;

abstract contract MyCommand is CommandBase {
    string private constant INPUT = "{ bytes32 asset, uint amount, #status }";

    uint private immutable inputSpec;
    uint private immutable descriptor;
    uint private immutable id;

    event PaymentSeen(bytes32 asset, uint amount, uint status);

    constructor() {
        inputSpec = schema(INPUT, 1, uint32(64 + Sizes.Status), uint32(64 + Sizes.Status), uint32(64 + Sizes.Status));
        (id, descriptor) = command("myCommand", Specs.Empty, inputSpec, Specs.Empty, 0);
    }

    function unpackPayment(
        Execution memory exec
    ) private view returns (bytes32 asset, uint amount, uint status) {
        (uint abs, uint payloadCur) = exec.enter(inputSpec, 64);

        asset = Blocks.read32(abs);
        amount = uint(Blocks.read32(abs + 32));

        // The fixed-size outer schema leaves exactly one STATUS block.
        (status,) = payloadCur.unpackStatus();
    }

    function myCommand(
        bytes calldata context
    ) external onlyCommand returns (bytes memory, uint) {
        // Each callback decodes one payment with the command-local unpack helper.
        return runCommand(id, descriptor, context, myCommandOne);
    }

    function myCommandOne(Execution memory exec) private {
        (bytes32 asset, uint amount, uint status) = unpackPayment(exec);
        emit PaymentSeen(asset, amount, status);
    }
}

// Concrete host so the example can be deployed and the command can be called in tests.
contract ExampleHost is Host, MyCommand {
    constructor(uint rootzero) Host(rootzero) {}
}
