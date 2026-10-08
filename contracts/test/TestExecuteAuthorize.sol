// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Cursors} from "../utils/Cursors.sol";

import {Host} from "../core/Host.sol";
import {Pipeline} from "../core/Pipeline.sol";
import {ExecuteAuthorize} from "../Endpoints.sol";

/// @dev Test-only entrypoint accepts arbitrary accounts to exercise adapter checks.
contract TestExecuteAuthorize is Host, Pipeline, ExecuteAuthorize {
    constructor(uint cmdr) Host(cmdr, "TestExecuteAuthorize") {}

    function execute(
        uint cmd, bytes32 account, bytes memory state, uint inputCur, uint value
    ) internal override returns (bool, bytes memory, uint) {
        if (cmd == authorizeId()) return executeAuthorize(account, state, inputCur, value);
        return (false, "", 0);
    }

    function testPipe(bytes32 account, bytes memory state, bytes calldata steps) external payable returns (uint) {
        return pipe(account, state, Cursors.wrap(steps), msg.value);
    }

    function adminAccount() external view returns (bytes32) { return admin; }
    function commandId() external view returns (uint) { return authorizeId(); }
    function isAuthorized(uint node) external view returns (bool) { return nodes[node]; }
}
