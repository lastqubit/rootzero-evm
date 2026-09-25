// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Pipeline} from "../core/Pipeline.sol";
import {AccessDenied} from "../core/Access.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Cursors} from "../utils/Cursors.sol";

/// @dev Synthetic credits exercise arithmetic boundaries without modeling ETH backing.
contract TestPipelineOptimization is Pipeline {
    mapping(uint => bool) public trusted;
    uint public calls;
    bytes32 public lastInput;
    event Called(bytes input, uint assigned);

    constructor() {
        trusted[localId()] = true;
        trusted[externalId()] = true;
    }
    function localId() public view returns (uint) { return uint160(address(this)); }
    function externalId() public view returns (uint) {
        return uint160(address(this)) | uint(uint32(this.command.selector)) << 160;
    }
    function revoke(uint cmd) external { trusted[cmd] = false; }
    function enforceCommand(uint cmd) internal view override returns (bytes4, address) {
        if (!trusted[cmd]) revert AccessDenied();
        return (bytes4(uint32(cmd >> 160)), address(uint160(cmd)));
    }
    function record(bytes calldata input, uint value) private returns (uint credit) {
        ++calls;
        lastInput = keccak256(input);
        emit Called(input, value);
        if (input.length >= 32) {
            assembly ("memory-safe") { credit := calldataload(input.offset) }
        }
    }
    function execute(uint cmd, bytes32, bytes memory state, bytes calldata input, uint value)
        internal override returns (bool, bytes memory, uint)
    {
        if (cmd != localId()) return (false, state, 0);
        enforceCommand(cmd);
        return (true, state, record(input, value));
    }
    function command(bytes calldata context) external payable returns (bytes memory, uint) {
        (uint abs,) = Cursors.bounds(context);
        (, bytes calldata state, bytes calldata input,) = Blocks.unpackContext(abs);
        return (state, record(input, msg.value));
    }
    function measure(bytes calldata steps, uint budget, bytes memory state)
        external payable returns (uint used, uint remaining)
    {
        uint initial = gasleft();
        remaining = pipe(bytes32(0), state, steps, budget);
        used = initial - gasleft();
    }
}
