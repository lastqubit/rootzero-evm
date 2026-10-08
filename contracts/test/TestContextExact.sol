// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Cursors} from "../utils/Cursors.sol";

contract TestContextExact {
    function contextExact(bytes calldata data) external pure returns (bytes32 account, bytes memory state, bytes memory input) {
        uint stateCur;
        uint inputCur;
        (account, stateCur, inputCur) = Blocks.unpackContextExact(Cursors.wrap(data) | (uint(123) << 128));
        assert(stateCur >> 64 == 0 && inputCur >> 64 == 0);
        state = Encoder.allocate(Cursors.length(stateCur));
        input = Encoder.allocate(Cursors.length(inputCur));
        Encoder.copy(Encoder.pos(state, 0), stateCur);
        Encoder.copy(Encoder.pos(input, 0), inputCur);
    }

}
