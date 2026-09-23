// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks, Cur, Decoders, Quote, Position, Specs, Writer, Writers} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {Positions} from "../utils/Positions.sol";
import {Sizes} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestQuote {
    using Decoders for Cur;
    using Writers for Writer;
    using Executions for Execution;

    function metadata() external pure returns (uint, uint, string memory) {
        return (Specs.Quote, Sizes.Quote, Schemas.Quote);
    }

    function check(bytes calldata input, Position memory position) external pure returns (Quote memory next) {
        Cur memory cur = Decoders.open(input);
        Positions.requireQuoted(position, cur.unpackQuoteValue());
        return cur.unpackQuoteValue();
    }

    function create(Quote memory quote) external pure returns (bytes memory) {
        return Blocks.createQuote(quote.asset, quote.liability, quote.limits);
    }

    function write(Quote memory quote, bool scalar) external pure returns (bytes memory) {
        Writer memory writer = Writers.init(Specs.Quote, 1);
        if (scalar) writer.appendQuote(quote.asset, quote.liability, quote.limits);
        else writer.appendQuote(quote);
        return writer.finish();
    }

    function decode(bytes calldata input, bool scalar) external pure returns (Quote memory quote) {
        Cur memory cur = Decoders.open(input);
        if (scalar) (quote.asset, quote.liability, quote.limits) = cur.unpackQuote();
        else quote = cur.unpackQuoteValue();
    }

    function execute(bytes calldata context, bool scalar) external pure returns (bytes memory) {
        Execution memory exec;
        exec.openContext(Executions.describe(Specs.Position, Specs.Quote, Specs.Quote, 0), 0, context);
        while (exec.more()) {
            exec.unpackPosition();
            if (scalar) {
                (bytes32 asset, bytes32 liability, uint limits) = exec.unpackQuote();
                exec.outputQuote(asset, liability, limits);
            } else {
                exec.outputQuote(exec.unpackQuoteValue());
            }
        }
        return exec.finish();
    }
}
