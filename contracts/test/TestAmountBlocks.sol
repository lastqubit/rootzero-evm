// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AssetAmount, Execute, Blocks, Encoder, Cursors, Keys, Specs, Sizes, Headers, Schemas, Execution, Executions} from "../Codec.sol";

contract TestAmountBlocks {
    function layout() external pure returns (bytes4 key, uint spec, uint header, uint size, string memory schema) {
        return (Keys.Amount, Specs.Amount, Headers.Amount, Sizes.Amount, Schemas.Amount);
    }

    function encode(uint amount, uint capacity) external pure returns (
        bytes memory created, bytes memory written, bytes memory executed
    ) {
        created = Encoder.createAmount(amount);
        (bytes memory buffer, uint cur) = Encoder.init(capacity);
        (buffer, cur) = Encoder.writeAmount(cur, buffer, amount);
        written = Encoder.finish(cur, buffer);
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        Executions.outputAmount(exec, amount);
        executed = Executions.finish(exec);
    }

    function decode(bytes calldata source, uint size, bool execution) external pure returns (
        uint amount, uint consumed, uint remaining
    ) {
        uint abs = Cursors.base(source);
        uint cur = Cursors.create(abs, abs + size);
        if (execution) {
            Execution memory exec;
            exec.input = cur;
            amount = Executions.unpackAmount(exec);
            cur = exec.input;
        } else {
            (amount, cur) = Blocks.unpackAmount(cur);
        }
        consumed = Cursors.position(cur) - abs;
        remaining = Cursors.length(cur);
    }
    function assetLayout() external pure returns (bytes4, uint, uint, uint, string memory) {
        return (Keys.AssetAmount, Specs.AssetAmount, Headers.AssetAmount, Sizes.AssetAmount, Schemas.AssetAmount);
    }

    function encodeAsset(bytes32 asset, uint amount, uint capacity) external pure returns (
        bytes memory created, bytes memory written, bytes memory executed, bytes memory structured
    ) {
        created = Encoder.createAssetAmount(asset, amount);
        (bytes memory buffer, uint cur) = Encoder.init(capacity);
        (buffer, cur) = Encoder.writeAssetAmount(cur, buffer, asset, amount);
        written = Encoder.finish(cur, buffer);
        Execution memory exec;
        (exec.buffer, exec.output) = Encoder.init(capacity);
        Executions.outputAssetAmount(exec, asset, amount);
        executed = Executions.finish(exec);
        (exec.buffer, exec.output) = Encoder.init(capacity);
        Executions.outputAssetAmount(exec, AssetAmount(asset, amount));
        structured = Executions.finish(exec);
    }

    function decodeAsset(bytes calldata source, uint size, uint mode) external pure returns (
        bytes32 asset, uint amount, uint remaining
    ) {
        uint abs = Cursors.base(source);
        uint cur = Cursors.create(abs, abs + size);
        if (mode == 0) {
            (asset, amount, cur) = Blocks.unpackAssetAmount(cur);
        } else {
            Execution memory exec;
            exec.input = cur;
            if (mode == 1) {
                (asset, amount) = Executions.unpackAssetAmount(exec);
            } else {
                AssetAmount memory value = Executions.unpackAssetAmountValue(exec);
                (asset, amount) = (value.asset, value.amount);
            }
            cur = exec.input;
        }
        remaining = Cursors.length(cur);
    }

    function decodeFixed(bytes calldata source, bool paired) external pure returns (bytes32 asset, uint amount) {
        (uint abs, uint end) = Execute.bounds(Cursors.wrap(source), paired ? Sizes.AssetAmount : Sizes.Amount);
        require(abs < end);
        if (paired) return Execute.unpackAssetAmount(abs);
        return (bytes32(0), Execute.unpackAmount(abs));
    }
}
