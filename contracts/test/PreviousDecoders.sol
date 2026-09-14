// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AssetAmount, AssetLiability, AccountAsset, HostAsset, AccountAmount, HostAmount, HostAccountAsset, Position, Tx} from "../core/Types.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Sizes, Specs} from "../codec/Specs.sol";
import {Cursors, Cur} from "../utils/Cursors.sol";
import {OutOfBounds, UnconsumedData} from "../utils/Errors.sol";


library PreviousDecoders {
    using Cursors for uint;
    function unpackBytes(Cur memory cur) internal pure returns (bytes calldata data) {
        uint end;
        (data, end) = Blocks.unpackBytes(cur.state.position());
        cur.state = cur.state.seek(end);
    }

    function unpackStep(
        Cur memory cur
    ) internal pure returns (uint cmd, uint value, bytes calldata input) {
        uint abs = cur.state.position();
        uint end;
        (cmd, value, input, end) = Blocks.unpackStep(abs);
        cur.state = cur.state.seek(end);
    }

    function consume(Cur memory cur, uint spec) internal pure returns (uint body, uint end) {
        (body, end) = Blocks.enter(cur.state.position(), spec);
        cur.state = cur.state.seek(end);
    }

    function consume(Cur memory cur, bytes4 key) internal pure returns (uint body, uint end) {
        (body, end) = Blocks.enter(cur.state.position(), key);
        cur.state = cur.state.seek(end);
    }

    function unpackRaw(Cur memory cur, uint spec) internal pure returns (bytes calldata data) {
        uint end;
        (data, end) = Blocks.unpackRaw(cur.state.position(), spec);
        cur.state = cur.state.seek(end);
    }

    function unpackString(Cur memory cur) internal pure returns (string memory data) {
        bytes calldata value;
        uint end;
        (value, end) = Blocks.unpackString(cur.state.position());
        data = string(value);
        cur.state = cur.state.seek(end);
    }

    function unpackContext(
        Cur memory cur
    ) internal pure returns (bytes32 account, bytes calldata state, bytes calldata input) {
        uint abs = cur.state.position();
        uint end;
        (account, state, input, end) = Blocks.unpackContext(abs);
        cur.state = cur.state.seek(end);
    }

    function unpackRelay(
        Cur memory cur
    ) internal pure returns (bytes calldata input, bytes calldata steps) {
        uint abs = cur.state.position();
        uint end;
        (input, steps, end) = Blocks.unpackRelay(abs);
        cur.state = cur.state.seek(end);
    }

    function unpackLabel(Cur memory cur) internal pure returns (bytes32 namespace, string memory name) {
        uint abs = cur.state.position();
        uint end;
        (namespace, name, end) = Blocks.unpackLabel(abs);
        cur.state = cur.state.seek(end);
    }

    function unpackSchema(Cur memory cur) internal pure returns (uint spec, string memory body, bytes32 name) {
        uint abs = cur.state.position();
        uint end;
        (spec, body, name, end) = Blocks.unpackSchema(abs);
        cur.state = cur.state.seek(end);
    }

    function unpackRecover(
        Cur memory cur
    ) internal pure returns (uint handler, uint resources, bytes32 key, bytes calldata witness) {
        uint abs = cur.state.position();
        uint end;
        (handler, resources, key, witness, end) = Blocks.unpackRecover(abs);
        cur.state = cur.state.seek(end);
    }

    function unpackCall(
        Cur memory cur
    ) internal pure returns (uint target, uint resources, bytes calldata data) {
        uint abs = cur.state.position();
        uint end;
        (target, resources, data, end) = Blocks.unpackCall(abs);
        cur.state = cur.state.seek(end);
    }

    function unpackDispatch(
        Cur memory cur
    ) internal pure returns (uint portal, uint resources, bytes calldata payload) {
        uint abs = cur.state.position();
        uint end;
        (portal, resources, payload, end) = Blocks.unpackDispatch(abs);
        cur.state = cur.state.seek(end);
    }

    function unpackAnnotation(
        Cur memory cur
    ) internal pure returns (uint entity, bytes calldata data) {
        uint abs = cur.state.position();
        uint end;
        (entity, data, end) = Blocks.unpackAnnotation(abs);
        cur.state = cur.state.seek(end);
    }

    function tryConsumeEmpty(Cur memory cur, bytes4 key) internal pure returns (bool) {
        (uint position, uint end) = cur.state.bounds();
        (bytes4 current, uint len) = Blocks.peek(position, end);
        if (current != key || len != 0) return false;
        cur.state = cur.state.seek(position + Sizes.Header);
        return true;
    }

    function unpack32(Cur memory cur, uint spec) internal pure returns (bytes32 value) {
        uint abs;
        (cur.state, abs) = cur.state.consume(Sizes.B32);
        if (Blocks.header(abs, Specs.key(spec)) != 32) revert Blocks.InvalidBlock();
        assembly ("memory-safe") {
            value := calldataload(add(abs, 0x08))
        }
    }
}
