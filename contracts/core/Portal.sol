// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Blocks} from "../codec/Blocks.sol";
import {Calls} from "./Calls.sol";
import {Runtime} from "./Runtime.sol";
import {Logs} from "../codec/Logs.sol";
import {Codes} from "../utils/Codes.sol";
import {PortPipePayableSelector} from "../ports/Pipe.sol";

/// @notice Hook for forwarding a recoverable message through a transport boundary.
abstract contract ForwardHook {
    /// @notice Attempt to forward the message cursor, recording or returning its failure digest as needed.
    /// @param key Forwarding and recovery lookup key.
    /// @param messageCur Cursor over the encoded message to forward.
    /// @param value Native EVM value assigned to the forwarding attempt.
    /// @return miss Message digest retained for recovery when forwarding fails; zero on success.
    function forward(bytes32 key, uint messageCur, uint value) internal virtual returns (bytes32 miss);
}

/// @title Portal
/// @notice Base contract that forwards incoming contexts to its commander's pipeline.
abstract contract Portal is ForwardHook, Runtime {
    /// @dev Fixed recovery allowance; derived constructors may increase it for transport work.
    uint internal immutable gasReserve = 35_000;

    error BadWitness();

    mapping(bytes32 key => bytes32 digest) internal unresolved;

    /// @dev Return the pipe gas budget, or zero to skip delivery and try storage.
    /// Reserve call preparation, a cold CALL, fresh digest storage, the failure
    /// event, and return. Value overhead assumes an existing commander.
    /// Charge full memory cost conservatively, including already allocated memory.
    function forwardGas(uint length, uint value) internal view returns (uint gas) {
        uint free;
        assembly ("memory-safe") {
            free := mload(0x40)
        }
        uint words = (length + 31) / 32;
        // ABI header, padded message, and trailing zero write in Calls.tryRaw.
        uint endWords = (free + 68 + words * 32 + 32 + 31) / 32;
        // Two calldata copies and KECCAK cost 12 gas per message word.
        uint reserve = gasReserve + 12 * words + 3 * endWords + (endWords * endWords) / 512;
        if (value != 0) reserve += 9_000;
        gas = gasleft();
        gas = gas > reserve ? gas - reserve : 0;
    }

    /// @notice Try to forward the message cursor to the commander's payable pipeline port.
    /// @dev Records the digest when forwarding fails or is skipped for lack of gas.
    /// Recording itself still reverts if the remaining gas is insufficient.
    /// Successful return data is ignored. The commander's pipeline port settles
    /// any remainder when the last context's account is nonzero, returning zero credit.
    /// Empty input or a zero final account instead returns the unspent budget, which
    /// this transport also ignores. It does not decode messages or settle accounts.
    /// @param key Forwarding/recovery lookup key.
    /// @param messageCur Cursor over the encoded CONTEXT block stream to forward.
    /// @param value Native EVM value assigned to the forwarding attempt.
    /// @return miss Message digest recorded for recovery when forwarding fails; zero on success.
    function forward(bytes32 key, uint messageCur, uint value) internal override returns (bytes32 miss) {
        uint gas = forwardGas(Blocks.length(messageCur), value);
        if (gas > 0 && Calls.tryRaw(PortPipePayableSelector, commanderAddr, value, gas, messageCur)) return bytes32(0);

        miss = Blocks.hash(messageCur);
        unresolved[key] = miss;
        Logs.resolution(key, miss, Codes.HostUnresolved);
    }

    /// @notice Validate and consume a previously unresolved witness.
    /// @dev The witness must hash to the digest stored under `key`.
    /// Logs consumption of the key/digest record, not downstream delivery success.
    /// If a later recovery operation reverts, deletion and the log roll back together.
    /// @param key Recovery lookup key.
    /// @param witnessCur Cursor over the witness payload used to prove and replay recovery.
    /// @return resolvedCur The validated witness payload cursor.
    function resolve(bytes32 key, uint witnessCur) internal returns (uint resolvedCur) {
        bytes32 digest = unresolved[key];
        if (digest != Blocks.hash(witnessCur)) revert BadWitness();

        delete unresolved[key];
        Logs.resolution(key, digest, Codes.HostResolved);
        return witnessCur;
    }
}
