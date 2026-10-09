// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host} from "../Core.sol";
import {GetQuote, GetQuoteHook} from "../Endpoints.sol";
import {Blocks, Cursors, Encoder, Specs, Sizes, Headers, Schemas} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";

contract TestGetQuote is Host, GetQuote {
    mapping(bytes32 => mapping(bytes32 => bool)) private supported;
    mapping(bytes32 => mapping(bytes32 => uint)) private premiums;
    error UnsupportedPair();

    constructor() Host(0, "TestGetQuote", address(0)) {}

    function configure(bytes32 asset, bytes32 liability, uint premium) external {
        supported[asset][liability] = true;
        premiums[asset][liability] = premium;
    }

    function getQuote(bytes32 asset, uint amount, bytes32 liability) internal view override returns (uint) {
        if (!supported[asset][liability]) revert UnsupportedPair();
        return amount + premiums[asset][liability];
    }

    function catalog() external pure returns (uint, uint, uint, string memory) {
        return (Specs.QuoteRequest, Sizes.QuoteRequest, Headers.QuoteRequest, Schemas.QuoteRequest);
    }

    function create(bytes32 asset, uint amount, bytes32 liability) external pure returns (bytes memory) {
        return Encoder.createQuoteRequest(asset, amount, liability);
    }

    function write(bytes32 asset, uint amount, bytes32 liability) external pure returns (bytes memory) {
        (bytes memory buffer, uint cur) = Encoder.init(0);
        (buffer, cur) = Encoder.writeQuoteRequest(cur, buffer, asset, amount, liability);
        return Encoder.finish(cur, buffer);
    }

    function decode(bytes calldata input) external pure returns (bytes32 asset, uint amount, bytes32 liability, uint remaining) {
        uint next;
        (asset, amount, liability, next) = Blocks.unpackQuoteRequest(Cursors.wrap(input));
        remaining = Blocks.length(next);
    }

    function echo(bytes calldata input) external pure returns (bytes memory) {
        Execution memory exec;
        Executions.openInput(exec, Executions.describe(0, Specs.QuoteRequest, Specs.QuoteRequest), 0, input);
        while (Executions.more(exec)) {
            (bytes32 asset, uint amount, bytes32 liability) = Executions.unpackQuoteRequest(exec);
            Executions.outputQuoteRequest(exec, asset, amount, liability);
        }
        return Executions.finish(exec);
    }
}
