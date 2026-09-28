// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {MalformedBlocks} from "./LegacyErrors.sol";
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {LegacyBuffers} from "./LegacyBuffers.sol";
import {Sizes, Specs} from "../codec/Specs.sol";
import {Cursors} from "../utils/Cursors.sol";
import {InsufficientValue, OutOfBounds, UnexpectedPosition, UnconsumedData, InvalidBlock} from "../utils/Errors.sol";
import {Budget} from "../core/Budget.sol";
import {AssetAmount, AssetLiability, AccountAsset, HostAsset, AccountAmount, HostAmount, HostAccountAsset, Position, Tx} from "../core/Types.sol";

import {Execution} from "../execution/Execution.sol";

/// @dev Previous helper algorithms adapted to separate input/state cursors.
/// Shared execution layout, LegacyBlocks, and LegacyBuffers isolate helper changes.
library PreviousExecutions {
    function rawState(Execution memory exec) internal pure returns (bytes calldata data) {
        uint cur = exec.state;
        if ((cur & (1 << 64)) == 0) return msg.data[0:0];
        uint current = uint32(cur);
        uint end = uint32(cur >> 32);
        if (end > msg.data.length || current > end) revert MalformedBlocks();
        return msg.data[current:end];
    }

    function takeRawState(Execution memory exec) internal pure returns (bytes calldata data) {
        data = rawState(exec);
        if ((exec.state & (1 << 64)) == 0) return data;
        takeState(exec, data.length);
    }

    function takeRawBalances(Execution memory exec) internal pure returns (bytes calldata data) {
        data = rawState(exec);
        for (uint consumed; consumed < data.length; consumed += Sizes.Balance) {
            unpackBalance(exec);
        }
    }

    function rawInput(Execution memory exec) internal pure returns (bytes calldata data) {
        uint cur = exec.input;
        if ((cur & (1 << 64)) == 0) return msg.data[0:0];
        uint current = uint32(cur);
        uint end = uint32(cur >> 32);
        if (end > msg.data.length || current > end) revert MalformedBlocks();
        return msg.data[current:end];
    }

    function takeRawInput(Execution memory exec) internal pure returns (bytes calldata data) {
        data = rawInput(exec);
        if ((exec.input & (1 << 64)) == 0) return data;
        take(exec, data.length);
    }

    function takeState(Execution memory exec, uint amount) private pure returns (uint abs) {
        uint cur = exec.state;
        abs = uint32(cur);
        uint end = uint32(cur >> 32);
        if (amount > end - abs) revert OutOfBounds();
        unchecked {
            exec.state = cur + amount;
        }
    }

    function take(Execution memory exec, uint amount) internal pure returns (uint abs) {
        uint cur = exec.input;
        abs = uint32(cur);
        uint end = uint32(cur >> 32);
        if (amount > end - abs) revert OutOfBounds();
        unchecked {
            exec.input = cur + amount;
        }
    }

    function seekInput(Execution memory exec, uint next) private pure {
        uint cur = exec.input;
        uint current = uint32(cur);
        uint end = uint32(cur >> 32);
        if (next < current || next > end) revert OutOfBounds();
        exec.input = (cur & ~uint(type(uint32).max)) | next;
    }

    function unpackBalance(Execution memory exec) internal pure returns (bytes32 asset, uint amount) {
        uint abs = takeState(exec, Sizes.Balance);
        (asset, amount) = LegacyBlocks.unpackBalance(abs);
    }

    function useValue(Execution memory exec, uint value) internal pure returns (uint) {
        if (value > exec.budget) revert InsufficientValue();
        exec.budget -= value;
        return value;
    }

    function unpack32(Execution memory exec, uint spec) internal pure returns (bytes32 value) {
        uint abs = take(exec, Sizes.B32);
        if (LegacyBlocks.header(abs, Specs.key(spec)) != 32) revert InvalidBlock();
        assembly ("memory-safe") {
            value := calldataload(add(abs, 0x08))
        }
    }

    function consume(Execution memory exec, uint spec) internal pure returns (uint body, uint end) {
        uint current = uint32(exec.input);
        (body, end) = LegacyBlocks.enter(current, spec);
        seekInput(exec, end);
    }

    function consume(Execution memory exec, bytes4 key) internal pure returns (uint body, uint end) {
        uint current = uint32(exec.input);
        (body, end) = LegacyBlocks.enter(current, key);
        seekInput(exec, end);
    }

    function unpackBytes(Execution memory exec) internal pure returns (bytes calldata data) {
        uint abs = uint32(exec.input);
        uint end;
        (data, end) = LegacyBlocks.unpackBytes(abs);
        seekInput(exec, end);
    }

    function unpackString(Execution memory exec) internal pure returns (string memory data) {
        uint abs = uint32(exec.input);
        (bytes calldata value, uint end) = LegacyBlocks.unpackString(abs);
        data = string(value);
        seekInput(exec, end);
    }

    function unpackStep(Execution memory exec) internal pure returns (uint cmd, uint value, bytes calldata input) {
        uint abs = uint32(exec.input);
        uint end;
        (cmd, value, input, end) = LegacyBlocks.unpackStep(abs);
        seekInput(exec, end);
    }

    function unpackCall(
        Execution memory exec
    ) internal pure returns (uint target, uint resources, bytes calldata data) {
        uint abs = uint32(exec.input);
        uint end;
        (target, resources, data, end) = LegacyBlocks.unpackCall(abs);
        seekInput(exec, end);
    }

    function unpackContext(
        Execution memory exec
    ) internal pure returns (bytes32 account, bytes calldata state, bytes calldata input) {
        uint abs = uint32(exec.input);
        uint end;
        (account, state, input, end) = LegacyBlocks.unpackContext(abs);
        seekInput(exec, end);
    }

    function unpackRelay(Execution memory exec) internal pure returns (bytes calldata input, bytes calldata steps) {
        uint abs = uint32(exec.input);
        uint end;
        (input, steps, end) = LegacyBlocks.unpackRelay(abs);
        seekInput(exec, end);
    }

    function unpackDispatch(
        Execution memory exec
    ) internal pure returns (uint portal, uint resources, bytes calldata payload) {
        uint abs = uint32(exec.input);
        uint end;
        (portal, resources, payload, end) = LegacyBlocks.unpackDispatch(abs);
        seekInput(exec, end);
    }

    function unpackAnnotation(Execution memory exec) internal pure returns (uint entity, bytes calldata data) {
        uint abs = uint32(exec.input);
        uint end;
        (entity, data, end) = LegacyBlocks.unpackAnnotation(abs);
        seekInput(exec, end);
    }

    function unpackLabel(Execution memory exec) internal pure returns (bytes32 namespace, string memory name) {
        uint abs = uint32(exec.input);
        bytes calldata value;
        uint end;
        (namespace, value, end) = LegacyBlocks.unpackLabel(abs);
        name = string(value);
        seekInput(exec, end);
    }

    function unpackSchema(Execution memory exec) internal pure returns (uint spec, string memory body) {
        uint abs = uint32(exec.input);
        bytes calldata value;
        uint end;
        (spec, value, end) = LegacyBlocks.unpackSchema(abs);
        body = string(value);
        seekInput(exec, end);
    }

    function unpackRecover(
        Execution memory exec
    ) internal pure returns (uint handler, uint resources, bytes32 key, bytes calldata witness) {
        uint abs = uint32(exec.input);
        uint end;
        (handler, resources, key, witness, end) = LegacyBlocks.unpackRecover(abs);
        seekInput(exec, end);
    }

    function unpackRaw(Execution memory exec, uint spec) internal pure returns (bytes calldata data) {
        uint abs = uint32(exec.input);
        uint end;
        (data, end) = LegacyBlocks.unpackRaw(abs, spec);
        seekInput(exec, end);
    }

    function reserve(Execution memory exec, uint amount, uint touch) internal pure returns (uint i) {
        (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, amount, touch);
    }

    function reserve(Execution memory exec, uint size) private pure returns (uint i) {
        (exec.output, exec.buffer, i) = LegacyBuffers.reserve(exec.output, exec.buffer, size, size);
    }

    function outputStep(Execution memory exec, uint cmd, uint value, bytes memory input) internal pure {
        uint size = Sizes.Step + input.length;
        uint i = reserve(exec, size);
        LegacyBlocks.writeStep(exec.buffer, i, cmd, value, input);
    }

    function outputCall(Execution memory exec, uint target, uint resources, bytes memory payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        LegacyBlocks.writeCall(exec.buffer, i, target, resources, payload);
    }

    function outputDispatch(Execution memory exec, uint portal, uint resources, bytes memory payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        LegacyBlocks.writeDispatch(exec.buffer, i, portal, resources, payload);
    }

    function outputRelay(Execution memory exec, bytes memory input, bytes memory steps) internal pure {
        uint size = 3 * Sizes.Header + input.length + steps.length;
        uint i = reserve(exec, size);
        LegacyBlocks.writeRelay(exec.buffer, i, input, steps);
    }

    function outputContext(
        Execution memory exec,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure {
        uint size = Sizes.B32 + 2 * Sizes.Header + state.length + input.length;
        uint i = reserve(exec, size);
        LegacyBlocks.writeContext(exec.buffer, i, account, state, input);
    }

    function outputRecover(
        Execution memory exec,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes memory witness
    ) internal pure {
        uint size = Sizes.B96 + Sizes.Header + witness.length;
        uint i = reserve(exec, size);
        LegacyBlocks.writeRecover(exec.buffer, i, handler, resources, recoverykey, witness);
    }

    function outputLabel(Execution memory exec, bytes32 namespace, string memory name) internal pure {
        uint size = Sizes.B32 + Sizes.Header + bytes(name).length;
        uint i = reserve(exec, size);
        LegacyBlocks.writeLabel(exec.buffer, i, namespace, name);
    }

    function outputSchema(Execution memory exec, uint spec, string memory body) internal pure {
        uint size = Sizes.B32 + Sizes.Header + bytes(body).length;
        uint i = reserve(exec, size);
        LegacyBlocks.writeSchema(exec.buffer, i, spec, body);
    }

    function outputCopyBlock(Execution memory exec, uint spec, bytes calldata data) internal pure {
        Specs.validate(spec, data.length);
        uint size = Sizes.Header + data.length;
        uint i = reserve(exec, size);
        LegacyBlocks.copy(exec.buffer, i, Specs.key(spec), data);
    }

    function outputCopyList(Execution memory exec, bytes calldata value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(exec, size);
        LegacyBlocks.copyList(exec.buffer, i, value);
    }

    function outputCopyBytes(Execution memory exec, bytes calldata value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(exec, size);
        LegacyBlocks.copyBytes(exec.buffer, i, value);
    }

    function outputCopyString(Execution memory exec, string calldata value) internal pure {
        uint size = Sizes.Header + bytes(value).length;
        uint i = reserve(exec, size);
        LegacyBlocks.copyString(exec.buffer, i, value);
    }

    function outputCopyStep(Execution memory exec, uint cmd, uint value, bytes calldata input) internal pure {
        uint size = Sizes.Step + input.length;
        uint i = reserve(exec, size);
        LegacyBlocks.copyStep(exec.buffer, i, cmd, value, input);
    }

    function outputCopyCall(Execution memory exec, uint target, uint resources, bytes calldata payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        LegacyBlocks.copyCall(exec.buffer, i, target, resources, payload);
    }

    function outputCopyDispatch(
        Execution memory exec,
        uint portal,
        uint resources,
        bytes calldata payload
    ) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        LegacyBlocks.copyDispatch(exec.buffer, i, portal, resources, payload);
    }

    function outputCopyRelay(Execution memory exec, bytes calldata input, bytes calldata steps) internal pure {
        uint size = 3 * Sizes.Header + input.length + steps.length;
        uint i = reserve(exec, size);
        LegacyBlocks.copyRelay(exec.buffer, i, input, steps);
    }

    function outputCopyContext(
        Execution memory exec,
        bytes32 account,
        bytes calldata state,
        bytes calldata input
    ) internal pure {
        uint size = Sizes.B32 + 2 * Sizes.Header + state.length + input.length;
        uint i = reserve(exec, size);
        LegacyBlocks.copyContext(exec.buffer, i, account, state, input);
    }

    function outputCopyRecover(
        Execution memory exec,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes calldata witness
    ) internal pure {
        uint size = Sizes.B96 + Sizes.Header + witness.length;
        uint i = reserve(exec, size);
        LegacyBlocks.copyRecover(exec.buffer, i, handler, resources, recoverykey, witness);
    }
}
