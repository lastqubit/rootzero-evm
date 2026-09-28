// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {UnexpectedValue} from "../utils/Errors.sol";
import {Assets} from "../utils/Assets.sol";
import {Cursors} from "../utils/Cursors.sol";

using Cursors for uint;

contract TestErc20CursorHelper {
    function expectErc20Amount(uint cur, uint i) private view returns (address token, uint amount) {
        bytes32 asset;
        cur = cur.seek(i);
        (asset, amount, cur) = Blocks.unpackAmount(cur);
        token = Assets.erc20Addr(asset);
    }

    function expectErc20Balance(uint cur, uint i) private view returns (address token, uint amount) {
        bytes32 asset;
        cur = cur.seek(i);
        (asset, amount, cur) = Blocks.unpackBalance(cur);
        token = Assets.erc20Addr(asset);
    }

    function expectErc20Custody(uint cur, uint i, uint host) private view returns (address token, uint amount) {
        uint actualHost;
        bytes32 asset;
        cur = cur.seek(i);
        (actualHost, asset, amount, cur) = Blocks.unpackCustody(cur);
        if (actualHost != host) revert UnexpectedValue();
        token = Assets.erc20Addr(asset);
    }

    function testExpectErc20Amount(bytes calldata source, uint i) external view returns (address token, uint amount) {
        uint cur = Cursors.wrap(source);
        return expectErc20Amount(cur, Cursors.base(source) + i);
    }

    function testRequireErc20Amount(bytes calldata source) external view returns (address token, uint amount, uint i) {
        uint cur = Cursors.wrap(source);
        bytes32 asset;
        (asset, amount, cur) = Blocks.unpackAmount(cur);
        token = Assets.erc20Addr(asset);
        i = cur.position() - Cursors.base(source);
    }

    function testExpectErc20Balance(bytes calldata source, uint i) external view returns (address token, uint amount) {
        uint cur = Cursors.wrap(source);
        return expectErc20Balance(cur, Cursors.base(source) + i);
    }

    function testRequireErc20Balance(bytes calldata source) external view returns (address token, uint amount, uint i) {
        uint cur = Cursors.wrap(source);
        bytes32 asset;
        (asset, amount, cur) = Blocks.unpackBalance(cur);
        token = Assets.erc20Addr(asset);
        i = cur.position() - Cursors.base(source);
    }

    function testExpectErc20Custody(
        bytes calldata source,
        uint i,
        uint host
    ) external view returns (address token, uint amount) {
        uint cur = Cursors.wrap(source);
        return expectErc20Custody(cur, Cursors.base(source) + i, host);
    }

    function testRequireErc20Custody(
        bytes calldata source,
        uint host
    ) external view returns (address token, uint amount, uint i) {
        uint cur = Cursors.wrap(source);
        uint actualHost;
        bytes32 asset;
        (actualHost, asset, amount, cur) = Blocks.unpackCustody(cur);
        if (actualHost != host) revert UnexpectedValue();
        token = Assets.erc20Addr(asset);
        i = cur.position() - Cursors.base(source);
    }

}
