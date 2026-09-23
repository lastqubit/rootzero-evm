// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Calls} from "../core/Calls.sol";
import {Pipeline} from "../core/Pipeline.sol";
import {Nodes} from "../utils/Nodes.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Execution, Executions} from "../execution/Execution.sol";

contract TestCommandCalls is Pipeline {
    error TargetFailure(uint value);
    event BytesCalled(bytes data, uint value);
    event ContextCalled(bytes context, uint value);

    function testPipeUsage(
        bytes32 account,
        bytes memory state,
        bytes calldata steps
    ) external returns (uint allocated, uint usedGas) {
        uint start;
        assembly ("memory-safe") { start := mload(0x40) }
        uint beforeGas = gasleft();
        pipe(account, state, steps, 0);
        usedGas = beforeGas - gasleft();
        assembly ("memory-safe") { allocated := sub(mload(0x40), start) }
    }

    function testPipe(
        bytes32 account,
        bytes memory state,
        bytes calldata steps
    ) external payable returns (uint remaining) {
        return pipe(account, state, steps, msg.value);
    }

    function testTryRawCall(
        bytes4 selector,
        address target,
        uint value,
        bytes memory input
    ) external payable returns (bool) {
        return Calls.tryRaw(selector, target, value, input);
    }

    function testTryRawCallCopy(
        bytes4 selector,
        address target,
        uint value,
        bytes calldata input
    ) external payable returns (bool) {
        return Calls.tryRawCopy(selector, target, value, input);
    }

    function testTryRawCallGas(
        bytes4 selector,
        address target,
        uint value,
        uint gasLimit,
        bytes memory input
    ) external payable returns (bool) {
        return Calls.tryRaw(selector, target, value, gasLimit, input);
    }

    function testTryRawCallCopyGas(
        bytes4 selector,
        address target,
        uint value,
        uint gasLimit,
        bytes calldata input
    ) external payable returns (bool) {
        return Calls.tryRawCopy(selector, target, value, gasLimit, input);
    }

    function testRawCall(
        bytes4 selector,
        address target,
        uint value,
        bytes memory input,
        bool expectEmpty
    ) external payable returns (bytes memory, uint) {
        return Calls.raw(selector, target, value, input, expectEmpty);
    }

    function testRawCallCopy(
        bytes4 selector,
        address target,
        uint value,
        bytes calldata input,
        bool expectEmpty
    ) external payable returns (bytes memory, uint) {
        return Calls.rawCopy(selector, target, value, input, expectEmpty);
    }

    function echoPort(bytes calldata data) external payable returns (bytes memory, uint) {
        emit BytesCalled(data, msg.value);
        return (data, msg.value);
    }

    function testExecutionRawCall(
        bytes4 selector, address target, uint value, bytes memory input, bool expectEmpty
    ) external payable returns (bytes memory out, uint remaining) {
        Execution memory exec = Executions.open();
        out = Executions.rawCall(exec, selector, target, value, input, expectEmpty);
        remaining = exec.budget;
    }

    function testExecutionRawCallCopy(
        bytes4 selector, address target, uint value, bytes calldata input, bool expectEmpty
    ) external payable returns (bytes memory out, uint remaining) {
        Execution memory exec = Executions.open();
        out = Executions.rawCallCopy(exec, selector, target, value, input, expectEmpty);
        remaining = exec.budget;
    }

    function returnRaw(bytes calldata data) external payable {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, data.offset, data.length)
            return(ptr, data.length)
        }
    }

    function testRawQuery(
        bytes4 selector,
        address target,
        bytes memory input
    ) external view returns (bytes memory) {
        return Calls.rawQuery(selector, target, input);
    }

    function noArgs() external pure returns (uint) {
        return 42;
    }

    function echoBytes(bytes calldata data) external payable returns (bytes memory) {
        emit BytesCalled(data, msg.value);
        return data;
    }

    function queryBytes(bytes calldata data) external pure returns (bytes memory) {
        return data;
    }

    function failBytes(bytes calldata data) external pure {
        revert TargetFailure(data.length);
    }

    function command(bytes calldata context) external payable returns (bytes memory, uint) {
        return ("", uint(keccak256(context)) ^ msg.value);
    }

    /// @dev Hash the full ABI call, including padding outside the context bytes.
    function inspectCommand(bytes calldata) external payable returns (bytes memory, uint) {
        return ("", uint(keccak256(msg.data)) ^ msg.value);
    }

    function replaceState(bytes calldata context) external payable returns (bytes memory, uint) {
        uint abs;
        assembly ("memory-safe") { abs := context.offset }
        (, , bytes calldata input, ) = Blocks.unpackContext(abs);
        emit ContextCalled(context, msg.value);
        return (input, msg.value);
    }

    function discard(bytes calldata) external pure returns (bytes memory, uint) {
        return ("", 0);
    }

    function failing(bytes calldata) external pure returns (bytes memory, uint) {
        revert TargetFailure(7);
    }

    function malformed(bytes calldata) external pure returns (bytes memory, uint) {
        assembly ("memory-safe") {
            mstore(0, 0x20)
            mstore(0x20, 0)
            mstore(0x40, 0)
            return(0, 0x60)
        }
    }

    function shortReturn(bytes calldata) external pure returns (bytes memory, uint) {
        assembly ("memory-safe") {
            return(0, 0x40)
        }
    }

    function oversizedLength(bytes calldata) external pure returns (bytes memory, uint) {
        assembly ("memory-safe") {
            mstore(0, 0x40)
            mstore(0x20, 0)
            mstore(0x40, 0x20)
            return(0, 0x60)
        }
    }

    function trailingData(bytes calldata) external pure returns (bytes memory, uint) {
        assembly ("memory-safe") {
            mstore(0, 0x40)
            mstore(0x20, 0)
            mstore(0x40, 0)
            mstore(0x60, 0)
            return(0, 0x80)
        }
    }

    function enforceCommand(uint cmd) internal pure virtual override returns (bytes4 selector, address target) {
        uint node = Nodes.command(cmd);
        selector = bytes4(uint32(node >> 160));
        target = address(uint160(node));
    }

    function execute(
        uint,
        bytes32,
        bytes memory state,
        bytes calldata,
        uint
    ) internal pure override returns (bool, bytes memory, uint) {
        return (false, state, 0);
    }
}

/// @dev Poison temporary memory immediately before invokeCommand builds its call.
contract TestDirtyCommandCalls is TestCommandCalls {
    function enforceCommand(uint cmd) internal pure override returns (bytes4 selector, address target) {
        (selector, target) = super.enforceCommand(cmd);
        assembly ("memory-safe") {
            let start := mload(0x40)
            for { let p := start } lt(p, add(start, 0x4000)) { p := add(p, 0x20) } {
                mstore(p, not(0))
            }
        }
    }
}
