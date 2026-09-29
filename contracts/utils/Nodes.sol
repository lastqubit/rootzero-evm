// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Layout} from "./Layout.sol";
import {InvalidId, InvalidContract} from "./Errors.sol";
import {Ids} from "./Ids.sol";
import {ensureAddr, isFamily, matchesBase, toLocalBase} from "./Utils.sol";

/// @title Nodes
/// @notice Encoding and decoding helpers for 256-bit node identifiers.
///
/// Node IDs share a common layout:
///   - bits [255:224] — 4-byte type prefix (`Host`, `Command`, `Port`, etc.)
///   - bits [223:192] — current `block.chainid` (makes IDs chain-local)
///   - bits [191:160] — 4-byte ABI selector (commands, ports, queries, and guards)
///   - bits [159:0]   — 160-bit EVM contract address
///
/// An opaque node uses `[0x02][Node][subtype][bytes29(hash)]`. The callable
/// target must be resolved by lookup
/// or witness data before dispatch.
///
/// The helpers in this library validate and deconstruct structured node IDs.
library Nodes {
    /// @dev 16-bit family tag shared by all node types (Evm + Node category).
    uint16 constant Family = (uint16(Layout.Evm) << 8) | uint16(Layout.Node);
    /// @dev Full 4-byte type prefix for chain/domain nodes.
    uint32 constant Chain = (uint32(Layout.Evm) << 24) | (uint32(Layout.Node) << 16) | (uint32(Layout.Chain) << 8);
    /// @dev Full 4-byte type prefix for host nodes.
    uint32 constant Host = (uint32(Layout.Evm) << 24) | (uint32(Layout.Node) << 16) | (uint32(Layout.Host) << 8);
    /// @dev Full 4-byte type prefix for command nodes.
    uint32 constant Command = (uint32(Layout.Evm) << 24) | (uint32(Layout.Node) << 16) | (uint32(Layout.Command) << 8);
    /// @dev Full 4-byte type prefix for port nodes.
    uint32 constant Port = (uint32(Layout.Evm) << 24) | (uint32(Layout.Node) << 16) | (uint32(Layout.Port) << 8);
    /// @dev Full 4-byte type prefix for query nodes.
    uint32 constant Query = (uint32(Layout.Evm) << 24) | (uint32(Layout.Node) << 16) | (uint32(Layout.Query) << 8);
    /// @dev Full 4-byte type prefix for guard action nodes.
    uint32 constant Guard = (uint32(Layout.Evm) << 24) | (uint32(Layout.Node) << 16) | (uint32(Layout.Guard) << 8);

    /// @notice Return true if `node` is a host node ID.
    function isHost(uint node) internal pure returns (bool) {
        return uint32(node >> 224) == Host;
    }

    /// @notice Return true if `node` is a command node ID.
    function isCommand(uint node) internal pure returns (bool) {
        return (uint32(node >> 224) & 0xffffff00) == Command;
    }

    /// @notice Return true if `node` is a port node ID.
    function isPort(uint node) internal pure returns (bool) {
        return (uint32(node >> 224) & 0xffffff00) == Port;
    }

    /// @notice Return true if `node` is a query node ID.
    function isQuery(uint node) internal pure returns (bool) {
        return (uint32(node >> 224) & 0xffffff00) == Query;
    }

    /// @notice Return true if `node` is a guard action node ID.
    function isGuard(uint node) internal pure returns (bool) {
        return (uint32(node >> 224) & 0xffffff00) == Guard;
    }

    /// @notice Return true if `node` belongs to the EVM node family.
    function isEvm(uint node) internal pure returns (bool) {
        return isFamily(node, Family);
    }

    /// @notice Return true if `node` is opaque.
    function isOpaque(uint node) internal pure returns (bool) {
        return Ids.isOpaque(bytes32(node), Layout.Node);
    }

    /// @notice Return true if `node` belongs to the EVM node family on the current chain.
    function isLocal(uint node) internal view returns (bool) {
        return isEvm(node) && uint32(node >> 192) == block.chainid;
    }

    /// @notice Assert that `value` is a host node ID and return it as a node.
    /// @param value Value to validate.
    /// @return node The same `value` if it is a host node.
    function host(uint value) internal pure returns (uint node) {
        if (!isHost(value)) revert InvalidId();
        return value;
    }

    /// @notice Assert that `value` is a command node ID and return it as a node.
    /// @param value Value to validate.
    /// @return node The same `value` if it is a command node.
    function command(uint value) internal pure returns (uint node) {
        if (!isCommand(value)) revert InvalidId();
        return value;
    }

    /// @notice Assert that `value` is a port node ID and return it as a node.
    /// @param value Value to validate.
    /// @return node The same `value` if it is a port node.
    function port(uint value) internal pure returns (uint node) {
        if (!isPort(value)) revert InvalidId();
        return value;
    }

    /// @notice Assert that `value` is a query node ID and return it as a node.
    /// @param value Value to validate.
    /// @return node The same `value` if it is a query node.
    function query(uint value) internal pure returns (uint node) {
        if (!isQuery(value)) revert InvalidId();
        return value;
    }

    /// @notice Assert that `value` is a guard action node ID and return it as a node.
    /// @param value Value to validate.
    /// @return node The same `value` if it is a guard action node.
    function guard(uint value) internal pure returns (uint node) {
        if (!isGuard(value)) revert InvalidId();
        return value;
    }

    /// @notice Assert that `value` belongs to the EVM node family and return it as a node.
    /// @param value Value to validate.
    /// @return node The same `value` if it is an EVM node.
    function evm(uint value) internal pure returns (uint node) {
        if (!isEvm(value)) revert InvalidId();
        return value;
    }

    /// @notice Assert that `value` is an opaque node and return it unchanged.
    /// @param value Node ID to validate.
    /// @return node The same `value` if it is opaque.
    function opaque(uint value) internal pure returns (uint node) {
        if (!isOpaque(value)) revert InvalidId();
        return value;
    }

    /// @notice Assert that `value` belongs to the EVM node family on the current chain and return it as a node.
    /// @param value Value to validate.
    /// @return node The same `value` if it is local.
    function local(uint value) internal view returns (uint node) {
        if (!isLocal(value)) revert InvalidId();
        return value;
    }

    /// @notice Assert that `node` is a command ID and return its embedded ABI selector.
    /// @param node Node ID to validate.
    /// @return selector 4-byte command selector stored in bits [191:160].
    function commandSelector(uint node) internal pure returns (bytes4 selector) {
        return bytes4(uint32(command(node) >> 160));
    }

    /// @notice Assert that `node` is a port ID and return its embedded ABI selector.
    /// @param node Node ID to validate.
    /// @return selector 4-byte port selector stored in bits [191:160].
    function portSelector(uint node) internal pure returns (bytes4 selector) {
        return bytes4(uint32(port(node) >> 160));
    }

    /// @notice Assert that `node` is a query ID and return its embedded ABI selector.
    /// @param node Node ID to validate.
    /// @return selector 4-byte query selector stored in bits [191:160].
    function querySelector(uint node) internal pure returns (bytes4 selector) {
        return bytes4(uint32(query(node) >> 160));
    }

    /// @notice Assert that `node` is a guard action ID and return its embedded ABI selector.
    /// @param node Node ID to validate.
    /// @return selector 4-byte guard selector stored in bits [191:160].
    function guardSelector(uint node) internal pure returns (bytes4 selector) {
        return bytes4(uint32(guard(node) >> 160));
    }

    /// @notice Assert that `value` is the host node of `target` on the current chain.
    /// @param value Value to validate.
    /// @param target Expected host contract address.
    /// @return node The same `value` if it matches `target`.
    function matchHost(uint value, address target) internal view returns (uint node) {
        if (value != toHost(target)) revert InvalidId();
        return value;
    }

    /// @notice Build the chain node ID for the current chain.
    /// @return node Chain node ID with zero selector and `address(0)` payload.
    function localChain() internal view returns (uint node) {
        return toLocalBase(Chain);
    }

    /// @notice Build a chain-local host ID for `target`.
    /// @param target Host contract address.
    /// @return node Host node ID on the current chain.
    function toHost(address target) internal view returns (uint node) {
        return toLocalBase(Host) | uint(uint160(target));
    }

    /// @notice Build a chain-local command ID for the given endpoint name and contract.
    /// @param name Command function name.
    /// @param target Command contract address.
    /// @return node Command node ID embedding both the selector and address.
    function toCommand(string memory name, address target) internal view returns (uint node) {
        return toCommand(name, target, 0);
    }

    /// @notice Build a chain-local command ID carrying endpoint behavior flags.
    function toCommand(string memory name, address target, uint8 flags) internal view returns (uint node) {
        node = toLocalBase(Command | uint32(flags)) | uint(uint160(target));
        node |= uint(uint32(toSelector(name, "(bytes)"))) << 160;
    }

    /// @notice Build a chain-local port ID for the given endpoint name and contract.
    /// @param name Port function name.
    /// @param target Port contract address.
    /// @return node Port node ID embedding both the selector and address.
    function toPort(string memory name, address target) internal view returns (uint node) {
        return toPort(name, target, 0);
    }

    /// @notice Build a chain-local port ID carrying endpoint behavior flags.
    function toPort(string memory name, address target, uint8 flags) internal view returns (uint node) {
        node = toLocalBase(Port | uint32(flags)) | uint(uint160(target));
        node |= uint(uint32(toSelector(name, "(bytes)"))) << 160;
    }

    /// @notice Build a chain-local query ID for the given endpoint name and contract.
    /// @param name Query function name.
    /// @param target Query contract address.
    /// @return node Query node ID embedding both the selector and address.
    function toQuery(string memory name, address target) internal view returns (uint node) {
        return toQuery(name, target, 0);
    }

    /// @notice Build a chain-local query ID carrying endpoint behavior flags.
    function toQuery(string memory name, address target, uint8 flags) internal view returns (uint node) {
        node = toLocalBase(Query | uint32(flags)) | uint(uint160(target));
        node |= uint(uint32(toSelector(name, "(bytes)"))) << 160;
    }

    /// @notice Build a chain-local guard action ID for the given endpoint name and contract.
    /// @param name Guard action function name.
    /// @param target Guard action contract address.
    /// @return node Guard action node ID embedding both the selector and address.
    function toGuard(string memory name, address target) internal view returns (uint node) {
        return toGuard(name, target, 0);
    }

    /// @notice Build a chain-local guard ID carrying endpoint behavior flags.
    function toGuard(string memory name, address target, uint8 flags) internal view returns (uint node) {
        node = toLocalBase(Guard | uint32(flags)) | uint(uint160(target));
        node |= uint(uint32(toSelector(name, "(bytes)"))) << 160;
    }

    /// @dev Derive an ABI selector from an endpoint name and argument signature.
    function toSelector(string memory name, string memory args) private pure returns (bytes4) {
        return bytes4(keccak256(bytes(string.concat(name, args))));
    }

    /// @notice Derive an opaque node ID from a keccak preimage.
    /// @param preimage Preimage encoded as `0x01 || Node || subtype || payload`.
    /// @return node `[0x02][Node][subtype][bytes29(keccak256(preimage))]`.
    function toKeccak(bytes memory preimage) internal pure returns (uint node) {
        return uint(Ids.toKeccak(Layout.Node, preimage));
    }

    /// @notice Assert that `node` matches the opaque keccak ID for `preimage`.
    /// @param node Opaque node ID to validate.
    /// @param preimage Preimage whose first byte is `0x01`.
    /// @return The same `node` value if it matches.
    function matchKeccak(uint node, bytes memory preimage) internal pure returns (uint) {
        if (node != uint(Ids.toKeccak(Layout.Node, preimage))) revert InvalidId();
        return node;
    }

    /// @notice Decode any local node ID into its selector and contract address.
    /// @dev Validates only that `node` belongs to the local EVM node family.
    /// Callers may validate a specific node type or require a nonzero address first.
    /// @param node Local EVM node ID to decode.
    /// @return selector ABI selector stored in bits [191:160].
    /// @return target Contract address stored in bits [159:0].
    function decode(uint node) internal view returns (bytes4 selector, address target) {
        node = local(node);
        selector = bytes4(uint32(node >> 160));
        target = address(uint160(node));
    }

    /// @notice Extract the contract address from any local node ID.
    /// Reverts if `node` does not belong to the local node family or carries `address(0)`.
    /// @param node Node ID.
    /// @return Contract address in the lower 160 bits of `node`.
    function addr(uint node) internal view returns (address) {
        return ensureAddr(address(uint160(local(node))));
    }

    /// @notice Extract the contract address from a local host ID.
    /// Reverts if `node` does not match the local host base or carries `address(0)`.
    /// @param node Host node ID.
    /// @return Host contract address in the lower 160 bits of `node`.
    function hostAddr(uint node) internal view returns (address) {
        if (!matchesBase(bytes32(node), toLocalBase(Host))) revert InvalidId();
        return ensureAddr(address(uint160(node)));
    }

    /// @notice Validate a local host ID with deployed bytecode and return its address.
    /// @dev Uses hostAddr's host-type, chain, and nonzero-address checks, then
    /// requires a zero selector lane for a canonical host ID.
    /// Rejects EOAs, future deployment addresses, contracts under construction, and
    /// precompiles without bytecode with InvalidContract. Does not validate an interface.
    /// @param node Local host ID whose contract must already be deployed.
    /// @return target Validated host contract address.
    function ensureContract(uint node) internal view returns (address target) {
        target = hostAddr(node);
        if (uint32(node >> 160) != 0) revert InvalidId();
        if (target.code.length == 0) revert InvalidContract();
    }
}
