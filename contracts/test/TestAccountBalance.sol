// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AccountBalance} from "../core/Types.sol";
import {Blocks, Encoder, Cursors, Keys, Specs, Sizes, Headers, Schemas} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";

contract TestAccountBalance {
    using Executions for Execution;
    function definition() external pure returns (bytes4, uint, uint, uint, string memory) {
        return (Keys.AccountBalance, Specs.AccountBalance, Headers.AccountBalance, Sizes.AccountBalance, Schemas.AccountBalance);
    }
    function encode(AccountBalance memory value) external pure returns (bytes memory single, bytes memory pair) {
        single = Encoder.createAccountBalance(value.account, value.asset, value.amount);
        uint cur;
        (pair, cur) = Encoder.init(0);
        (pair, cur) = Encoder.writeAccountBalance(cur, pair, value.account, value.asset, value.amount);
        (pair, cur) = Encoder.writeAccountBalance(cur, pair, value.account, value.asset, value.amount);
        pair = Encoder.finish(cur, pair);
    }
    function decode(bytes calldata data, uint size) external pure returns (AccountBalance memory first, uint remaining, uint metadata) {
        uint cur = Cursors.wrap(data);
        uint abs = uint32(cur);
        cur = abs | ((abs + size) << 32) | (uint(123) << 64);
        (first.account, first.asset, first.amount, cur) = Blocks.unpackAccountBalance(cur);
        remaining = uint32(cur >> 32) - uint32(cur);
        metadata = cur >> 64;
    }
    function bounce(bytes calldata data) external pure returns (bytes memory) {
        Execution memory exec;
        exec.openInput(Executions.describe(0, Specs.AccountBalance, Specs.AccountBalance), 0, data);
        while (exec.more()) {
            AccountBalance memory value = exec.unpackAccountBalanceValue();
            exec.outputAccountBalance(value);
            // Output owns a copy, independent of the decoded struct.
            value.amount = 0;
        }
        return exec.finish();
    }
}
