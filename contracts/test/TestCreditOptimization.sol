// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {Logs as PreviousLogs} from "./PreviousEventLogs.sol";

import {ExecuteCreditAccount} from "../commands/Credit.sol";
import {Execute} from "../codec/Execute.sol";
import {Logs} from "../codec/Logs.sol";
import {Encoder} from "../codec/Encoder.sol";
import {Keys} from "../codec/Keys.sol";
import {Sizes} from "../codec/Specs.sol";
import {UnexpectedInput} from "../utils/Errors.sol";
import {Cursors} from "../utils/Cursors.sol";
import {Runtime} from "../core/Runtime.sol";

abstract contract CreditMeasure is ExecuteCreditAccount {
    uint internal sum;
    constructor() Runtime(0) {}
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        require(amount != type(uint).max, "hook");
        unchecked { sum += uint(account) ^ uint(asset) ^ amount; }
    }
    function run(bytes memory state, uint inputCur, uint value) internal virtual returns (bool, bytes memory, uint);
    function measure(bytes memory state, uint inputCur, uint value) external returns (
        uint used, bool handled, bytes memory output, uint credit, uint checksum, bytes32 stateHash
    ) {
        uint initial = gasleft();
        (handled, output, credit) = run(state, inputCur, value);
        used = initial - gasleft();
        checksum = sum;
        stateHash = keccak256(state);
    }
}

// Frozen credit adapter before reusing the default empty return value.
contract CreditBefore is CreditMeasure {
    function run(bytes memory state, uint inputCur, uint value) internal override returns (bool, bytes memory, uint) {
        return beforeCredit(bytes32(uint(9)), state, inputCur, value);
    }
    function beforeCredit(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (!Cursors.done(inputCur)) revert UnexpectedInput();
        (uint abs, uint end) = Execute.bounds(state, Sizes.Balance);

        PreviousLogs.memCopyWrap(creditAccountId(), Keys.State, state);

        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackBalanceMemory(abs);
            creditAccount(account, asset, amount);
            unchecked {
                abs += Sizes.Balance;
            }
        }

        return (true, "", value);
    }
}

contract CreditCurrent is CreditMeasure {
    function run(bytes memory state, uint inputCur, uint value) internal override returns (bool, bytes memory, uint) {
        return executeCreditAccount(bytes32(uint(9)), state, inputCur, value);
    }
}

contract CreditLogMeasure {
    function measure(bytes memory source, uint mode) external returns (uint used, bytes32 hash) {
        // Same ownership and initial memory for every logging alternative.
        bytes memory state = Encoder.allocate(source.length);
        Encoder.copy(Encoder.pos(state, 0), source, source.length);
        uint initial = gasleft();
        if (mode == 0) PreviousLogs.memCopyWrap(123, Keys.State, state);
        else if (mode == 1) {
            uint key = uint32(Keys.State);
            assembly ("memory-safe") {
                let size := mload(state)
                mstore(state, or(shl(32, key), size))
                log1(add(state, 24), add(size, 8), 123)
                mstore(state, size)
            }
        } else PreviousLogs.memWrap(123, Keys.State, state);
        used = initial - gasleft();
        hash = keccak256(state);
    }
}
