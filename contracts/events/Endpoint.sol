// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {EventEmitter} from "./Emitter.sol";

/// @title EndpointEvent
/// @notice Emitted during host deployment to publish a callable endpoint and its block specifications and lane codes.
abstract contract EndpointEvent is EventEmitter {
    string private constant ABI = "event Endpoint(uint indexed host, uint id, uint state, uint input, uint output)";

    /// @param host Host node ID that exposes the endpoint.
    /// @param id Endpoint node ID.
    /// @param state State lane: upper-half spec and lower-half codes; nonzero codes select logging.
    /// @param input Input lane: upper-half spec and lower-half codes; nonzero codes select logging.
    /// @param output Output lane: upper-half spec and lower-half codes; nonzero codes select logging.
    event Endpoint(uint indexed host, uint id, uint state, uint input, uint output);

    constructor() {
        emit EventAbi(ABI);
    }
}
