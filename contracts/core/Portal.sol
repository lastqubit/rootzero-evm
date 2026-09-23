// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Calls} from "./Calls.sol";
import {Runtime} from "./Runtime.sol";
import {ResolvedEvent} from "../events/Resolved.sol";
import {UnresolvedEvent} from "../events/Unresolved.sol";
import {PortPipePayableSelector} from "../ports/Pipe.sol";

/// @notice Hook for forwarding a recoverable message through a transport boundary.
abstract contract ForwardHook {
    /// @notice Attempt to forward `message`, recording or returning its failure digest as needed.
    /// @param key Forwarding and recovery lookup key.
    /// @param message Encoded message to forward.
    /// @param value Native EVM value assigned to the forwarding attempt.
    /// @return miss Message digest retained for recovery when forwarding fails; zero on success.
    function forward(bytes32 key, bytes calldata message, uint value) internal virtual returns (bytes32 miss);
}

/// @title Portal
/// @notice Base contract that forwards incoming contexts to its commander's pipeline.
abstract contract Portal is ForwardHook, Runtime, UnresolvedEvent, ResolvedEvent {
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
        // ABI header, padded message, and trailing zero write in Calls.tryRawCopy.
        uint endWords = (free + 68 + words * 32 + 32 + 31) / 32;
        // Two calldata copies and KECCAK cost 12 gas per message word.
        uint reserve = gasReserve + 12 * words + 3 * endWords + (endWords * endWords) / 512;
        if (value != 0) reserve += 9_000;
        gas = gasleft();
        gas = gas > reserve ? gas - reserve : 0;
    }

    /// @notice Try to forward `message` to the commander's payable pipeline port.
    /// @dev Records the digest when forwarding fails or is skipped for lack of gas.
    /// Recording itself still reverts if the remaining gas is insufficient.
    /// Successful return data is ignored. The commander's pipeline port settles
    /// any remainder to the last context's account and returns zero credit;
    /// this transport does not decode the message or perform account settlement.
    /// @param key Forwarding/recovery lookup key.
    /// @param message Encoded CONTEXT block stream to forward.
    /// @param value Native EVM value assigned to the forwarding attempt.
    /// @return miss Message digest recorded for recovery when forwarding fails; zero on success.
    function forward(bytes32 key, bytes calldata message, uint value) internal override returns (bytes32 miss) {
        uint gas = forwardGas(message.length, value);
        if (gas > 0 && Calls.tryRawCopy(PortPipePayableSelector, commanderAddr, value, gas, message)) return bytes32(0);

        miss = keccak256(message);
        unresolved[key] = miss;
        emit Unresolved(host, key, miss);
    }

    /// @notice Validate and consume a previously unresolved witness.
    /// @dev The witness must hash to the digest stored under `key`.
    /// If a later recovery operation reverts, this deletion is rolled back with it.
    /// @param key Recovery lookup key.
    /// @param witness Witness payload used to prove and replay recovery.
    /// @return resolved The validated witness payload.
    function resolve(bytes32 key, bytes calldata witness) internal returns (bytes calldata resolved) {
        if (unresolved[key] != keccak256(witness)) revert BadWitness();

        delete unresolved[key];
        return witness;
    }
}
