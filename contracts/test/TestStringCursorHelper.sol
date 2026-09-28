// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {LegacyBlocks} from "./LegacyBlocks.sol";

import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Specs} from "../Codec.sol";
import {Cursors} from "../utils/Cursors.sol";

contract TestStringCursorHelper {
    function testWriteStringBlock(string memory data) external pure returns (bytes memory) {
        (bytes memory wBuffer, uint w) = Encoder.init(Specs.allocation(Specs.String, 1));
        (wBuffer, w) = Encoder.writeString(w, wBuffer, bytes(data));
        return Encoder.finish(w, wBuffer);
    }

    function testToStringBlock(string memory data) external pure returns (bytes memory) {
        return LegacyBlocks.createString(data);
    }

    function testUnpackString(bytes calldata source) external pure returns (string memory data, uint i) {
        uint cur = Cursors.wrap(source);
        uint textCur;
        (textCur, cur) = Blocks.unpackString(cur);
        data = Blocks.toString(textCur);
        i = Cursors.position(cur) - Cursors.base(source);
    }

    function testUnpackLabel(
        bytes calldata source
    ) external pure returns (bytes32 namespace, string memory name, uint i) {
        uint cur = Cursors.wrap(source);
        uint textCur;
        (namespace, textCur, cur) = Blocks.unpackLabel(cur);
        name = Blocks.toString(textCur);
        i = Cursors.position(cur) - Cursors.base(source);
    }

    function testUnpackSchema(
        bytes calldata source
    ) external pure returns (uint spec, string memory body, uint i) {
        uint cur = Cursors.wrap(source);
        uint textCur;
        (spec, textCur, cur) = Blocks.unpackSchema(cur);
        body = Blocks.toString(textCur);
        i = Cursors.position(cur) - Cursors.base(source);
    }
}
