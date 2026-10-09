// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Specs} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";
import {QueryBase} from "./Base.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that expose exact-asset-amount quotes.
abstract contract GetQuoteHook {
    /// @notice Quote the liability required to receive exactly the requested asset amount.
    /// @dev Fees, pricing, availability, and unsupported-pair behavior belong to the implementation.
    /// @param asset Asset to receive.
    /// @param amount Requested quantity in the asset's native units.
    /// @param liability Asset used to pay for the requested asset.
    /// @return debt Required quantity in the liability's native units.
    function getQuote(bytes32 asset, uint amount, bytes32 liability) internal view virtual returns (uint debt);
}

/// @notice Read-only batched quotes, with one complete QUOTE per QUOTE_REQUEST in input order.
abstract contract GetQuote is QueryBase, GetQuoteHook {
    uint private immutable descriptor;

    constructor() {
        (, descriptor) = query("getQuote", Specs.QuoteRequest, Specs.Quote);
    }

    /// @notice Resolve a stream of quote requests; empty input returns empty output.
    /// @param input QUOTE_REQUEST blocks containing asset, exact asset amount, and liability.
    /// @return QUOTE blocks containing asset, amount, liability, and the hook's debt.
    function getQuote(bytes calldata input) external view returns (bytes memory) {
        return runQuery(descriptor, input, getQuoteOne);
    }

    function getQuoteOne(Execution memory exec) private view {
        (bytes32 asset, uint amount, bytes32 liability) = exec.unpackQuoteRequest();
        uint debt = getQuote(asset, amount, liability);
        exec.outputQuote(asset, amount, liability, debt);
    }
}
