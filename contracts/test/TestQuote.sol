// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {Cursors} from "../utils/Cursors.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Quote, Position, Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Sizes} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestQuote {
    using Executions for Execution;

    function metadata() external pure returns (uint, uint, string memory) {
        return (Specs.Quote, Sizes.Quote, Schemas.Quote);
    }

    function create(Quote memory quote) external pure returns (bytes memory) {
        return LegacyBlocks.createQuote(quote.asset, quote.amount, quote.liability, quote.debt);
    }

    function write(Quote memory quote) external pure returns (bytes memory) {
        (bytes memory writerBuffer, uint writer) = Encoder.init(Specs.allocation(Specs.Quote, 1));
        (writerBuffer, writer) = Encoder.writeQuote(writer, writerBuffer, quote.asset, quote.amount, quote.liability, quote.debt);
        return Encoder.finish(writer, writerBuffer);
    }

    function decode(bytes calldata input) external pure returns (Quote memory quote) {
        uint cur = Cursors.wrap(input);
        (quote.asset, quote.amount, quote.liability, quote.debt,) = Blocks.unpackQuote(cur);
    }

    function execute(bytes calldata context, bool scalar) external pure returns (bytes memory) {
        Execution memory exec;
        exec.openContext(Executions.describe(Specs.Position, Specs.Quote, Specs.Quote), 0, context);
        while (exec.more()) {
            exec.unpackPosition();
            if (scalar) {
                (bytes32 asset, uint amount, bytes32 liability, uint debt) = exec.unpackQuote();
                exec.outputQuote(asset, amount, liability, debt);
            } else {
                exec.outputQuote(exec.unpackQuoteValue());
            }
        }
        return exec.finish();
    }
}
