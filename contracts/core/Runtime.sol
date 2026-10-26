// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {TRUST_CHECK} from "./Trust.sol";
import {Assets} from "../utils/Assets.sol";
import {Accounts} from "../utils/Accounts.sol";
import {Nodes} from "../utils/Nodes.sol";

/// @title ChainAsset
/// @notice Shared chain asset identity for host helpers.
abstract contract ChainAsset {
    /// @dev Asset ID for the chain coin/token, bound to the current chain at deployment.
    bytes32 internal immutable chainAsset = Assets.toChain();
}

/// @title Runtime
/// @notice Shared runtime for host and chain asset identities.
abstract contract Runtime is ChainAsset {
    /// @dev Commander does not satisfy the host's external-commander policy.
    error InvalidCommander();

    /// @notice This runtime's host node ID, derived from its execution address at construction.
    uint public immutable host;

    /// @dev Commander host ID. Defaults to this contract's host ID when self-managed.
    uint internal immutable commander;

    /// @dev Native address embedded in `commander`, resolved once at construction.
    address internal immutable commanderAddr;

    /// @notice Bind the runtime to its execution address and local commander.
    /// @param cmdr Local host ID of the commander, or zero to make this runtime self-managed.
    /// @param self Execution address, or zero to use this deployment's address.
    constructor(uint cmdr, address self) {
        if (self == address(0)) self = address(this);
        host = Nodes.toHost(self);
        commander = cmdr == 0 ? host : cmdr;
        commanderAddr = Nodes.hostAddr(commander);
    }

    /// @notice Execution address embedded in this runtime's host node.
    /// @return Execution address encoded in the host node ID.
    function hostAddr() public view returns (address) {
        return address(uint160(host));
    }

    /// @notice This runtime's host account, preserving the host node's chain and address.
    /// @return Host account identifier for this runtime.
    function hostAccount() public view returns (bytes32) {
        return Accounts.toHost(host);
    }

    /// @notice Require a deployed commander host distinct from this runtime's execution address.
    /// @dev Opt-in policy for inheriting constructors. Remote means another host on the
    /// current chain. Rejects self-management with InvalidCommander and validates the
    /// canonical host ID and deployed bytecode via Nodes.ensureContract; no interface check.
    /// @return target Validated commander contract address.
    function ensureRemoteCommander() internal view returns (address target) {
        if (commanderAddr == hostAddr()) revert InvalidCommander();
        return Nodes.ensureContract(commander);
    }

    /// @notice Revert unless the commander trusts `id`.
    /// @dev The chain asset and the Rootzero asset are always trusted and return without a
    /// call. Otherwise a raw STATICCALL to the commander's `checkTrust()`; bubbles its
    /// `Untrusted(id)`. Uses scratch memory at the free pointer without allocating.
    /// @param id ID of any kind.
    function requireTrusted(bytes32 id) internal view {
        if (id == chainAsset || id == Assets.Rootzero) return;
        address target = commanderAddr;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, shl(224, TRUST_CHECK))
            mstore(add(ptr, 4), id)
            if iszero(staticcall(gas(), target, ptr, 36, 0, 0)) {
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
        }
    }

    /// @notice Revert unless the commander trusts each of `count` packed IDs at memory `ptr`.
    /// @dev Raw STATICCALL to the commander's `checkTrust()`; bubbles its `Untrusted(id)`.
    /// Builds the call in scratch memory past both the free pointer and the source IDs,
    /// so the IDs may also sit in unallocated scratch. Does not allocate.
    /// @param ptr Memory address of the first 32-byte ID.
    /// @param count Number of IDs.
    function requireTrusted(uint ptr, uint count) internal view {
        address target = commanderAddr;
        assembly ("memory-safe") {
            let length := mul(count, 32)
            let message := mload(0x40)
            let end := add(ptr, length)
            if gt(end, message) {
                message := end
            }
            mstore(message, shl(224, TRUST_CHECK))
            mcopy(add(message, 4), ptr, length)
            if iszero(staticcall(gas(), target, message, add(4, length), 0, 0)) {
                returndatacopy(message, 0, returndatasize())
                revert(message, returndatasize())
            }
        }
    }
}
