// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {Buffers} from "../codec/Buffers.sol";
import {Sizes, Specs} from "../codec/Specs.sol";
import {Cursors, Cur} from "../utils/Cursors.sol";
import {InsufficientValue, OutOfBounds, UnexpectedPosition, UnconsumedData} from "../utils/Errors.sol";
import {Budget} from "../core/Budget.sol";
import {
    AssetAmount,
    AssetLiability,
    AccountAsset,
    HostAsset,
    AccountAmount,
    HostAmount,
    HostAccountAsset,
    Position,
    Tx
} from "../core/Types.sol";

import {Execution} from "../execution/Execution.sol";

/// @dev Frozen execution helpers; shared Blocks and Buffers isolate execution changes.
library PreviousExecutions {
    function rawState(Execution memory exec) internal pure returns (bytes calldata data) {
        uint decoders = exec.decoders;
        if ((decoders & (1 << 128)) == 0) return msg.data[0:0];
        uint current = uint32(decoders >> 64);
        uint end = uint32(decoders >> 96);
        if (end > msg.data.length || current > end) revert Blocks.MalformedBlocks();
        return msg.data[current:end];
    }

    function takeRawState(Execution memory exec) internal pure returns (bytes calldata data) {
        data = rawState(exec);
        if ((exec.decoders & (1 << 128)) == 0) return data;
        takeState(exec, data.length);
    }

    function takeRawBalances(Execution memory exec) internal pure returns (bytes calldata data) {
        data = rawState(exec);
        for (uint consumed; consumed < data.length; consumed += Sizes.Balance) {
            unpackBalance(exec);
        }
    }

    function rawInput(Execution memory exec) internal pure returns (bytes calldata data) {
        uint decoders = exec.decoders;
        if ((decoders & (1 << 129)) == 0) return msg.data[0:0];
        uint current = uint32(decoders);
        uint end = uint32(decoders >> 32);
        if (end > msg.data.length || current > end) revert Blocks.MalformedBlocks();
        return msg.data[current:end];
    }

    function takeRawInput(Execution memory exec) internal pure returns (bytes calldata data) {
        data = rawInput(exec);
        if ((exec.decoders & (1 << 129)) == 0) return data;
        take(exec, data.length);
    }

    function takeState(Execution memory exec, uint amount) private pure returns (uint abs) {
        uint decoders = exec.decoders;
        abs = uint32(decoders >> 64);
        uint end = uint32(decoders >> 96);
        if (amount > end - abs) revert OutOfBounds();
        unchecked {
            exec.decoders = decoders + (amount << 64);
        }
    }

    function take(Execution memory exec, uint amount) internal pure returns (uint abs) {
        uint decoders = exec.decoders;
        abs = uint32(decoders);
        uint end = uint32(decoders >> 32);
        if (amount > end - abs) revert OutOfBounds();
        unchecked {
            exec.decoders = decoders + amount;
        }
    }

    function seekInput(Execution memory exec, uint next) private pure {
        uint decoders = exec.decoders;
        uint current = uint32(decoders);
        uint end = uint32(decoders >> 32);
        if (next < current || next > end) revert OutOfBounds();
        exec.decoders = (decoders & ~uint(type(uint32).max)) | next;
    }

    function unpackBalance(Execution memory exec) internal pure returns (bytes32 asset, uint amount) {
        uint abs = takeState(exec, Sizes.Balance);
        (asset, amount) = Blocks.unpackBalance(abs);
    }

    function useValue(Execution memory exec, uint value) internal pure returns (uint) {
        if (value > exec.budget) revert InsufficientValue();
        exec.budget -= value;
        return value;
    }

    function unpack32(Execution memory exec, uint spec) internal pure returns (bytes32 value) {
        uint abs = take(exec, Sizes.B32);
        if (Blocks.header(abs, Specs.key(spec)) != 32) revert Blocks.InvalidBlock();
        assembly ("memory-safe") {
            value := calldataload(add(abs, 0x08))
        }
    }

    function consume(Execution memory exec, uint spec) internal pure returns (uint body, uint end) {
        uint current = uint32(exec.decoders);
        (body, end) = Blocks.enter(current, spec);
        seekInput(exec, end);
    }

    function consume(Execution memory exec, bytes4 key) internal pure returns (uint body, uint end) {
        uint current = uint32(exec.decoders);
        (body, end) = Blocks.enter(current, key);
        seekInput(exec, end);
    }

    function unpackBytes(Execution memory exec) internal pure returns (bytes calldata data) {
        uint abs = uint32(exec.decoders);
        uint end;
        (data, end) = Blocks.unpackBytes(abs);
        seekInput(exec, end);
    }

    function unpackString(Execution memory exec) internal pure returns (string memory data) {
        uint abs = uint32(exec.decoders);
        (bytes calldata value, uint end) = Blocks.unpackString(abs);
        data = string(value);
        seekInput(exec, end);
    }

    function unpackStep(Execution memory exec) internal pure returns (uint cmd, uint value, bytes calldata input) {
        uint abs = uint32(exec.decoders);
        uint end;
        (cmd, value, input, end) = Blocks.unpackStep(abs);
        seekInput(exec, end);
    }

    function unpackCall(
        Execution memory exec
    ) internal pure returns (uint target, uint resources, bytes calldata data) {
        uint abs = uint32(exec.decoders);
        uint end;
        (target, resources, data, end) = Blocks.unpackCall(abs);
        seekInput(exec, end);
    }

    function unpackContext(
        Execution memory exec
    ) internal pure returns (bytes32 account, bytes calldata state, bytes calldata input) {
        uint abs = uint32(exec.decoders);
        uint end;
        (account, state, input, end) = Blocks.unpackContext(abs);
        seekInput(exec, end);
    }

    function unpackRelay(Execution memory exec) internal pure returns (bytes calldata input, bytes calldata steps) {
        uint abs = uint32(exec.decoders);
        uint end;
        (input, steps, end) = Blocks.unpackRelay(abs);
        seekInput(exec, end);
    }

    function unpackDispatch(
        Execution memory exec
    ) internal pure returns (uint portal, uint resources, bytes calldata payload) {
        uint abs = uint32(exec.decoders);
        uint end;
        (portal, resources, payload, end) = Blocks.unpackDispatch(abs);
        seekInput(exec, end);
    }

    function unpackAnnotation(Execution memory exec) internal pure returns (uint entity, bytes calldata data) {
        uint abs = uint32(exec.decoders);
        uint end;
        (entity, data, end) = Blocks.unpackAnnotation(abs);
        seekInput(exec, end);
    }

    function unpackLabel(Execution memory exec) internal pure returns (bytes32 namespace, string memory name) {
        uint abs = uint32(exec.decoders);
        uint end;
        (namespace, name, end) = Blocks.unpackLabel(abs);
        seekInput(exec, end);
    }

    function unpackSchema(Execution memory exec) internal pure returns (uint spec, string memory body, bytes32 name) {
        uint abs = uint32(exec.decoders);
        uint end;
        (spec, body, name, end) = Blocks.unpackSchema(abs);
        seekInput(exec, end);
    }

    function unpackRecover(
        Execution memory exec
    ) internal pure returns (uint handler, uint resources, bytes32 key, bytes calldata witness) {
        uint abs = uint32(exec.decoders);
        uint end;
        (handler, resources, key, witness, end) = Blocks.unpackRecover(abs);
        seekInput(exec, end);
    }

    function unpackRaw(Execution memory exec, uint spec) internal pure returns (bytes calldata data) {
        uint abs = uint32(exec.decoders);
        uint end;
        (data, end) = Blocks.unpackRaw(abs, spec);
        seekInput(exec, end);
    }

    function tryConsumeEmpty(Execution memory exec, bytes4 key) internal pure returns (bool) {
        uint decoders = exec.decoders;
        uint abs = uint32(decoders);
        uint limit = uint32(decoders >> 32);
        (bytes4 current, uint len) = Blocks.peek(abs, limit);
        if (current != key || len != 0) return false;
        uint next = abs + Sizes.Header;
        seekInput(exec, next);
        return true;
    }

    function reserve(Execution memory exec, uint amount, uint touch) internal pure returns (uint i) {
        (exec.writer, exec.output, i) = Buffers.reserve(exec.writer, exec.output, amount, touch);
    }

    function reserve(Execution memory exec, uint size) private pure returns (uint i) {
        (exec.writer, exec.output, i) = Buffers.reserve(exec.writer, exec.output, size, size);
    }

    function outputStep(Execution memory exec, uint cmd, uint value, bytes memory input) internal pure {
        uint size = Sizes.Step + input.length;
        uint i = reserve(exec, size);
        Blocks.writeStep(exec.output, i, cmd, value, input);
    }

    function outputCall(Execution memory exec, uint target, uint resources, bytes memory payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        Blocks.writeCall(exec.output, i, target, resources, payload);
    }

    function outputDispatch(Execution memory exec, uint portal, uint resources, bytes memory payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        Blocks.writeDispatch(exec.output, i, portal, resources, payload);
    }

    function outputRelay(Execution memory exec, bytes memory input, bytes memory steps) internal pure {
        uint size = 3 * Sizes.Header + input.length + steps.length;
        uint i = reserve(exec, size);
        Blocks.writeRelay(exec.output, i, input, steps);
    }

    function outputContext(
        Execution memory exec,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure {
        uint size = Sizes.B32 + 2 * Sizes.Header + state.length + input.length;
        uint i = reserve(exec, size);
        Blocks.writeContext(exec.output, i, account, state, input);
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
        Blocks.writeRecover(exec.output, i, handler, resources, recoverykey, witness);
    }

    function outputLabel(Execution memory exec, bytes32 namespace, string memory name) internal pure {
        uint size = Sizes.B32 + Sizes.Header + bytes(name).length;
        uint i = reserve(exec, size);
        Blocks.writeLabel(exec.output, i, namespace, name);
    }

    function outputSchema(Execution memory exec, uint spec, string memory body, bytes32 name) internal pure {
        uint size = Sizes.B64 + Sizes.Header + bytes(body).length;
        uint i = reserve(exec, size);
        Blocks.writeSchema(exec.output, i, spec, body, name);
    }

    function outputCopyBlock(Execution memory exec, uint spec, bytes calldata data) internal pure {
        Specs.validate(spec, data.length);
        uint size = Sizes.Header + data.length;
        uint i = reserve(exec, size);
        Blocks.copy(exec.output, i, Specs.key(spec), data);
    }

    function outputCopyList(Execution memory exec, bytes calldata value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(exec, size);
        Blocks.copyList(exec.output, i, value);
    }

    function outputCopyBytes(Execution memory exec, bytes calldata value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(exec, size);
        Blocks.copyBytes(exec.output, i, value);
    }

    function outputCopyString(Execution memory exec, string calldata value) internal pure {
        uint size = Sizes.Header + bytes(value).length;
        uint i = reserve(exec, size);
        Blocks.copyString(exec.output, i, value);
    }

    function outputCopyStep(Execution memory exec, uint cmd, uint value, bytes calldata input) internal pure {
        uint size = Sizes.Step + input.length;
        uint i = reserve(exec, size);
        Blocks.copyStep(exec.output, i, cmd, value, input);
    }

    function outputCopyCall(Execution memory exec, uint target, uint resources, bytes calldata payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        Blocks.copyCall(exec.output, i, target, resources, payload);
    }

    function outputCopyDispatch(
        Execution memory exec,
        uint portal,
        uint resources,
        bytes calldata payload
    ) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(exec, size);
        Blocks.copyDispatch(exec.output, i, portal, resources, payload);
    }

    function outputCopyRelay(Execution memory exec, bytes calldata input, bytes calldata steps) internal pure {
        uint size = 3 * Sizes.Header + input.length + steps.length;
        uint i = reserve(exec, size);
        Blocks.copyRelay(exec.output, i, input, steps);
    }

    function outputCopyContext(
        Execution memory exec,
        bytes32 account,
        bytes calldata state,
        bytes calldata input
    ) internal pure {
        uint size = Sizes.B32 + 2 * Sizes.Header + state.length + input.length;
        uint i = reserve(exec, size);
        Blocks.copyContext(exec.output, i, account, state, input);
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
        Blocks.copyRecover(exec.output, i, handler, resources, recoverykey, witness);
    }
}
