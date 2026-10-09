// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Host} from "../core/Host.sol";
import {Pipeline} from "../core/Pipeline.sol";
import {Balances} from "../core/Balances.sol";
import {ExecuteAuthorize, CreditAccountPort, GetBalance} from "../Endpoints.sol";
import {Cursors, Specs} from "../Codec.sol";

/// @dev Test-only pipeline accepts arbitrary accounts to exercise proxy identity.
contract TestRuntime is Host, Pipeline, ExecuteAuthorize, CreditAccountPort, GetBalance, Balances {
    constructor(uint cmdr, address self) Host(cmdr, "TestRuntime", self) {}

    function execute(uint cmd, bytes32 account, bytes memory state, uint input, uint value)
        internal virtual override returns (bool, bytes memory, uint)
    {
        if (cmd == authorizeId()) return executeAuthorize(account, state, input, value);
        return (false, "", 0);
    }

    function testPipe(bytes32 account, bytes calldata steps) external payable returns (uint) {
        return pipe(account, "", Cursors.wrap(steps), msg.value);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        creditTo(account, asset, amount);
    }

    function getBalance(bytes32 account, bytes32 asset) internal view override returns (uint) {
        return balances[account][asset];
    }

    function adminAccount() external view returns (bytes32) { return admin; }
    function commandId() external view returns (uint) { return authorizeId(); }
    function isAuthorized(uint node) external view returns (bool) { return nodes[node]; }
    function announce(uint node) external { introduceTo(node, "TestRuntime"); }
}

contract TestRuntimeV2 is TestRuntime {
    uint public immutable markId;
    uint public markers;

    constructor(address self) TestRuntime(0, self) {
        (markId, ) = command("mark", Specs.Empty, Specs.Empty, Specs.Empty, 0);
    }

    function execute(uint cmd, bytes32 account, bytes memory state, uint input, uint value)
        internal override returns (bool, bytes memory, uint)
    {
        if (cmd != markId) return super.execute(cmd, account, state, input, value);
        require(state.length == 0 && !Cursors.more(input));
        ++markers;
        return (true, "", value);
    }
}

/// @dev Test harness only: permits installing an implementation after proxy deployment.
contract TestRuntimeProxy {
    bytes32 private constant IMPLEMENTATION = bytes32(uint(keccak256("eip1967.proxy.implementation")) - 1);
    address private immutable owner = msg.sender;

    function upgrade(address implementation) external {
        require(msg.sender == owner && implementation.code.length != 0);
        bytes32 slot = IMPLEMENTATION;
        assembly ("memory-safe") { sstore(slot, implementation) }
    }

    fallback() external payable {
        bytes32 slot = IMPLEMENTATION;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let ok := delegatecall(gas(), sload(slot), ptr, calldatasize(), 0, 0)
            returndatacopy(ptr, 0, returndatasize())
            if iszero(ok) { revert(ptr, returndatasize()) }
            return(ptr, returndatasize())
        }
    }
}
