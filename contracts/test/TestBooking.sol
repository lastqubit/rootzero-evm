// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Booking} from "../core/Types.sol";
import {Blocks, Encoder, Cursors, Keys, Specs, Sizes, Headers, Schemas} from "../Codec.sol";
import {Execution, Executions} from "../execution/Execution.sol";

contract TestBooking {
    using Executions for Execution;
    function definition() external pure returns (bytes4, uint, uint, uint, string memory) {
        return (Keys.Booking, Specs.Booking, Headers.Booking, Sizes.Booking, Schemas.Booking);
    }
    function encode(Booking memory value) external pure returns (bytes memory single, bytes memory pair) {
        single = Encoder.createBooking(value);
        uint cur;
        (pair, cur) = Encoder.init(0);
        (pair, cur) = Encoder.writeBooking(cur, pair, value);
        (pair, cur) = Encoder.writeBooking(cur, pair, value);
        pair = Encoder.finish(cur, pair);
    }
    function decode(bytes calldata data, uint size) external pure returns (Booking memory first, uint remaining, uint metadata) {
        uint cur = Cursors.wrap(data);
        uint abs = uint32(cur);
        cur = abs | ((abs + size) << 32) | (uint(123) << 64);
        (first, cur) = Blocks.unpackBooking(cur);
        remaining = uint32(cur >> 32) - uint32(cur);
        metadata = cur >> 64;
    }
    function bounce(bytes calldata data) external pure returns (bytes memory) {
        Execution memory exec;
        exec.openInput(Executions.describe(0, Specs.Booking, Specs.Booking), 0, data);
        while (exec.more()) {
            Booking memory value = exec.unpackBooking();
            exec.outputBooking(value);
            // Output owns a copy, independent of the decoded struct.
            value.amount = 0;
        }
        return exec.finish();
    }
}
