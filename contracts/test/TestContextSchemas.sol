// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Keys, STATE_KEY, INPUT_KEY} from "../codec/Keys.sol";
import {Specs} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";
import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Execution, Executions} from "../execution/Execution.sol";

contract TestContextSchemas {
    function catalog() external pure returns (bytes4, bytes4, uint, uint, uint, uint, string memory) {
        return (Keys.State, Keys.Input, STATE_KEY, INPUT_KEY, Specs.State, Specs.Input, Schemas.Context);
    }

    function decode(bytes calldata source, bool execution) external pure returns (bytes32, bytes memory, bytes memory) {
        bytes32 account;
        uint state;
        uint input;
        if (execution) {
            Execution memory exec;
            Executions.openContext(exec, 0, 0, source);
            account = exec.account;
            state = exec.state;
            input = exec.input;
        } else {
            uint next;
            (account, state, input, next) = Blocks.unpackContext(Cursors.wrap(source));
            require(Cursors.done(next));
        }
        return (account, Cursors.toBytes(state), Cursors.toBytes(input));
    }

    function encode(bytes32 account, bytes calldata state, bytes calldata input, bool memorySource)
        external pure returns (bytes memory)
    {
        if (memorySource) return Encoder.createContext(account, state, input);
        return Encoder.createContext(account, Cursors.wrap(state), Cursors.wrap(input));
    }
}
