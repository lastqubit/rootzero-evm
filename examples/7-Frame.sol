// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

// Example 7: Custom Input Shape
//
// Discoverable custom input types define a context-local spec with a small
// literal or selector as its key, then publish it with a #schema annotation.
//
// For:
//
//   { bytes32 asset, uint amount, maybe #status }
//
// the encoded input item is:
//
//   PAYMENT(asset | amount | STATUS(status))
//
// or, when the command should use its default status:
//
//   PAYMENT(asset | amount | STATUS())

import {Host} from "../contracts/Core.sol";
import {Blocks, CommandBase, Execution, Executions, Sizes, Specs} from "../contracts/Commands.sol";
import {Keys} from "../contracts/Codec.sol";

using Executions for Execution;

abstract contract MyCommand is CommandBase {
    string private constant INPUT = "{ bytes32 asset, uint amount, maybe #status }";

    uint private immutable inputSpec;
    uint private immutable descriptor;

    event PaymentSeen(bytes32 asset, uint amount, uint status);

    constructor() {
        inputSpec = schema(1, uint32(64 + Sizes.Header), uint32(64 + Sizes.Status), uint32(64 + Sizes.Status), INPUT);
        (, descriptor) = command("myCommand", Specs.Empty, inputSpec, Specs.Empty, 0);
    }

    function unpackPayment(
        Execution memory exec
    ) private view returns (bytes32 asset, uint amount, uint status) {
        (uint abs, uint end) = exec.enter(inputSpec, 64);

        asset = Blocks.read32(abs);
        amount = uint(Blocks.read32(abs + 32));

        if (!exec.tryConsumeEmpty(Keys.Status)) {
            status = uint(exec.unpack32(Specs.Status));
        }

        exec.expect(end);
    }

    function myCommand(
        bytes calldata context
    ) external onlyCommand returns (bytes memory, uint) {
        // Each callback decodes one payment with the command-local unpack helper.
        return runCommand(context, descriptor, myCommandOne);
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
