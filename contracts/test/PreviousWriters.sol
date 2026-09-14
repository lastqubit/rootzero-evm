// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AssetAmount, AssetLiability, AccountAmount, HostAmount, Position, Tx} from "../core/Types.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Buffers} from "../codec/Buffers.sol";
import {Sizes, Specs} from "../codec/Specs.sol";

import {Writer} from "../codec/Writers.sol";

/// @dev Frozen writer bodies, with shared current buffer allocation.
library PreviousWriters {
    function reserve(Writer memory writer, uint advance, uint touch) private pure returns (uint i) {
        (writer.cur, writer.dst, i) = Buffers.reserve(writer.cur, writer.dst, advance, touch);
    }

    function reserve(Writer memory writer, uint size) private pure returns (uint i) {
        (writer.cur, writer.dst, i) = Buffers.reserve(writer.cur, writer.dst, size, size);
    }

    function appendBlock(Writer memory writer, uint spec, bytes memory data) internal pure {
        Specs.validate(spec, data.length);
        uint size = Sizes.Header + data.length;
        uint i = reserve(writer, size, size);
        Blocks.write(writer.dst, i, Specs.key(spec), data);
    }

    function appendStep(Writer memory writer, uint cmd, uint value, bytes memory input) internal pure {
        uint size = Sizes.Step + input.length;
        uint i = reserve(writer, size);
        Blocks.writeStep(writer.dst, i, cmd, value, input);
    }

    function appendCall(Writer memory writer, uint target, uint resources, bytes memory payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(writer, size);
        Blocks.writeCall(writer.dst, i, target, resources, payload);
    }

    function appendDispatch(Writer memory writer, uint portal, uint resources, bytes memory payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(writer, size);
        Blocks.writeDispatch(writer.dst, i, portal, resources, payload);
    }

    function appendRelay(Writer memory writer, bytes memory input, bytes memory steps) internal pure {
        uint size = 3 * Sizes.Header + input.length + steps.length;
        uint i = reserve(writer, size);
        Blocks.writeRelay(writer.dst, i, input, steps);
    }

    function appendContext(
        Writer memory writer,
        bytes32 account,
        bytes memory state,
        bytes memory input
    ) internal pure {
        uint size = Sizes.B32 + 2 * Sizes.Header + state.length + input.length;
        uint i = reserve(writer, size);
        Blocks.writeContext(writer.dst, i, account, state, input);
    }

    function appendRecover(
        Writer memory writer,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes memory witness
    ) internal pure {
        uint size = Sizes.B96 + Sizes.Header + witness.length;
        uint i = reserve(writer, size);
        Blocks.writeRecover(writer.dst, i, handler, resources, recoverykey, witness);
    }

    function appendLabel(
        Writer memory writer,
        bytes32 namespace,
        string memory name
    ) internal pure {
        uint size = Sizes.B32 + Sizes.Header + bytes(name).length;
        uint i = reserve(writer, size);
        Blocks.writeLabel(writer.dst, i, namespace, name);
    }

    function appendSchema(Writer memory writer, uint spec, string memory body, bytes32 name) internal pure {
        uint size = Sizes.B64 + Sizes.Header + bytes(body).length;
        uint i = reserve(writer, size);
        Blocks.writeSchema(writer.dst, i, spec, body, name);
    }

    function copyBlock(Writer memory writer, uint spec, bytes calldata data) internal pure {
        Specs.validate(spec, data.length);
        uint size = Sizes.Header + data.length;
        uint i = reserve(writer, size);
        Blocks.copy(writer.dst, i, Specs.key(spec), data);
    }

    function copyList(Writer memory writer, bytes calldata value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(writer, size);
        Blocks.copyList(writer.dst, i, value);
    }

    function copyBytes(Writer memory writer, bytes calldata value) internal pure {
        uint size = Sizes.Header + value.length;
        uint i = reserve(writer, size);
        Blocks.copyBytes(writer.dst, i, value);
    }

    function copyString(Writer memory writer, string calldata value) internal pure {
        uint size = Sizes.Header + bytes(value).length;
        uint i = reserve(writer, size);
        Blocks.copyString(writer.dst, i, value);
    }

    function copyStep(Writer memory writer, uint cmd, uint value, bytes calldata input) internal pure {
        uint size = Sizes.Step + input.length;
        uint i = reserve(writer, size);
        Blocks.copyStep(writer.dst, i, cmd, value, input);
    }

    function copyCall(Writer memory writer, uint target, uint resources, bytes calldata payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(writer, size);
        Blocks.copyCall(writer.dst, i, target, resources, payload);
    }

    function copyDispatch(Writer memory writer, uint portal, uint resources, bytes calldata payload) internal pure {
        uint size = Sizes.B64 + Sizes.Header + payload.length;
        uint i = reserve(writer, size);
        Blocks.copyDispatch(writer.dst, i, portal, resources, payload);
    }

    function copyRelay(Writer memory writer, bytes calldata input, bytes calldata steps) internal pure {
        uint size = 3 * Sizes.Header + input.length + steps.length;
        uint i = reserve(writer, size);
        Blocks.copyRelay(writer.dst, i, input, steps);
    }

    function copyContext(
        Writer memory writer,
        bytes32 account,
        bytes calldata state,
        bytes calldata input
    ) internal pure {
        uint size = Sizes.B32 + 2 * Sizes.Header + state.length + input.length;
        uint i = reserve(writer, size);
        Blocks.copyContext(writer.dst, i, account, state, input);
    }

    function copyRecover(
        Writer memory writer,
        uint handler,
        uint resources,
        bytes32 recoverykey,
        bytes calldata witness
    ) internal pure {
        uint size = Sizes.B96 + Sizes.Header + witness.length;
        uint i = reserve(writer, size);
        Blocks.copyRecover(writer.dst, i, handler, resources, recoverykey, witness);
    }
}
