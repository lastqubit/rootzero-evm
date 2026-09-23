// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import { Accounts } from "../utils/Accounts.sol";
import { Amounts, Assets } from "../utils/Assets.sol";
import { Ids } from "../utils/Ids.sol";
import { Layout } from "../utils/Layout.sol";
import { Nodes } from "../utils/Nodes.sol";
import { addrOr, applyBps, beforeBps, bytes32ToString, clear8, clear16, clear32, clear64, ensureContract, isFamily, matchesBase, toLocalBase, max8, max16, max32, max64, max128, max160, replace8, replace16, replace32, replace64 } from "../utils/Utils.sol";
import { CommandBase } from "../commands/Base.sol";
import { AccessDenied, enforceSender } from "../core/Access.sol";
import {Runtime} from "../core/Runtime.sol";
import {Execution, Executions} from "../execution/Execution.sol";

using Executions for Execution;

contract TestUtils is CommandBase {
    constructor() Runtime(0) {}

    function enforceCaller(address caller) internal view override returns (address) {
        if (caller != address(this)) revert AccessDenied();
        return caller;
    }

    function testAddrOr(address addr, address or_) external pure returns (address) {
        return addrOr(addr, or_);
    }

    function testEnsureContract(address target) external view returns (address) {
        return ensureContract(target);
    }

    function testRepresentations() external pure returns (uint8 rootzero, uint8 opaque, uint8 evm) {
        return (Layout.Rootzero, Layout.Opaque, Layout.Evm);
    }

    function testAssetSubtypes() external pure returns (uint8 derived, uint8 virtual_, uint8 erc20) {
        return (Layout.Derived, Layout.Virtual, Layout.Erc20);
    }

    function testEnforceSender(address expected) external view returns (address) {
        return enforceSender(expected);
    }

    function testIsOpaqueId(bytes32 id) external pure returns (bool) {
        return Ids.isOpaque(id);
    }

    function testOpaqueId(bytes32 id) external pure returns (bytes32) {
        return Ids.opaque(id);
    }

    function testToKeccak(bytes memory preimage) external pure returns (bytes32) {
        return Ids.toKeccak(preimage);
    }

    function testMatchKeccak(bytes32 id, bytes memory preimage) external pure returns (bytes32) {
        return Ids.matchKeccak(id, preimage);
    }

    function testToAdminAccount(address addr) external view returns (bytes32) {
        return Accounts.toAdmin(addr);
    }

    function testIsAccount(bytes32 value) external pure returns (bool) {
        return Accounts.isAccount(value);
    }

    function testCounterparty(bytes32 value) external pure returns (bytes32) {
        return Accounts.counterparty(value);
    }

    function testAccount(bytes32 value) external pure returns (bytes32) {
        return Accounts.account(value);
    }

    function testToUserAccount(address addr) external pure returns (bytes32) {
        return Accounts.toUser(addr);
    }

    function testToHostAccount(address addr) external view returns (bytes32) {
        return Accounts.toHost(addr);
    }

    function testHostNodeAccount(uint node) external pure returns (bytes32) {
        return Accounts.toHost(node);
    }

    function testIsHostAccount(bytes32 account) external pure returns (bool) {
        return Accounts.isHost(account);
    }

    function testHostAccount(bytes32 account) external pure returns (bytes32) {
        return Accounts.host(account);
    }

    function testAccountAddr(bytes32 account) external pure returns (address) {
        return Accounts.addr(account);
    }

    function testIsAdminAccount(bytes32 account) external pure returns (bool) {
        return Accounts.isAdmin(account);
    }

    function testIsUserAccount(bytes32 account) external pure returns (bool) {
        return Accounts.isUser(account);
    }

    function testAdminAccount(bytes32 account) external pure returns (bytes32) {
        return Accounts.admin(account);
    }

    function testUserAccount(bytes32 account) external pure returns (bytes32) {
        return Accounts.user(account);
    }

    function testIsEvmAccount(bytes32 account) external pure returns (bool) {
        return Accounts.isEvm(account);
    }

    function testIsOpaqueAccount(bytes32 account) external pure returns (bool) {
        return Accounts.isOpaque(account);
    }

    function testEvmAccount(bytes32 account) external pure returns (bytes32) {
        return Accounts.evm(account);
    }

    function testOpaqueAccount(bytes32 account) external pure returns (bytes32) {
        return Accounts.opaque(account);
    }

    function testToKeccakAccount(bytes memory preimage) external pure returns (bytes32) {
        return Accounts.toKeccak(preimage);
    }

    function testMatchKeccakAccount(bytes32 account, bytes memory preimage) external pure returns (bytes32) {
        return Accounts.matchKeccak(account, preimage);
    }

    function testToChain() external view returns (bytes32) {
        return Assets.toChain();
    }

    function testToErc20Asset(address addr) external view returns (bytes32) {
        return Assets.toErc20(addr);
    }

    function testIsEvmAsset(bytes32 asset) external pure returns (bool) {
        return Assets.isEvm(asset);
    }

    function testIsOpaqueAsset(bytes32 asset) external pure returns (bool) {
        return Assets.isOpaque(asset);
    }

    function testIsChain(bytes32 asset) external view returns (bool) {
        return Assets.isChain(asset);
    }

    function testIsRootzero(bytes32 asset) external pure returns (bool) {
        return Assets.isRootzero(asset);
    }

    function testEvmAsset(bytes32 asset) external pure returns (bytes32) {
        return Assets.evm(asset);
    }

    function testOpaqueAsset(bytes32 asset) external pure returns (bytes32) {
        return Assets.opaque(asset);
    }

    function testChain(bytes32 asset) external view returns (bytes32) {
        return Assets.chain(asset);
    }

    function testRootzero(bytes32 asset) external pure returns (bytes32) {
        return Assets.rootzero(asset);
    }

    function testToKeccakAsset(bytes memory preimage) external pure returns (bytes32) {
        return Assets.toKeccak(preimage);
    }

    function testMatchKeccakAsset(bytes32 asset, bytes memory preimage) external pure returns (bytes32) {
        return Assets.matchKeccak(asset, preimage);
    }

    function testResolveAmount(uint available, uint min, uint max) external pure returns (uint) {
        return Amounts.resolve(available, min, max);
    }

    function testEnsureAmount(uint amount) external pure returns (uint) {
        return Amounts.ensure(amount);
    }

    function testEnsureAmountRange(uint amount, uint min, uint max) external pure returns (uint) {
        return Amounts.ensure(amount, min, max);
    }

    function testLocalErc20Addr(bytes32 asset) external view returns (address) {
        return Assets.erc20Addr(asset);
    }

    function testMatchErc20(bytes32 asset, address token) external view returns (bytes32) {
        return Assets.matchErc20(asset, token);
    }

    function testToHostId(address addr) external view returns (uint) {
        return Nodes.toHost(addr);
    }

    function testLocalChainId() external view returns (uint) {
        return Nodes.localChain();
    }

    function testToCommandId(string memory name, address addr) external view returns (uint) {
        return Nodes.toCommand(name, addr);
    }

    function testToFlaggedCommandId(string memory name, address addr, uint8 flags) external view returns (uint) {
        return Nodes.toCommand(name, addr, flags);
    }

    function testToPortId(string memory name, address addr) external view returns (uint) {
        return Nodes.toPort(name, addr);
    }

    function testToQueryId(string memory name, address addr) external view returns (uint) {
        return Nodes.toQuery(name, addr);
    }

    function testToGuardId(string memory name, address addr) external view returns (uint) {
        return Nodes.toGuard(name, addr);
    }

    function testIsHost(uint node) external pure returns (bool) {
        return Nodes.isHost(node);
    }

    function testIsCommand(uint node) external pure returns (bool) {
        return Nodes.isCommand(node);
    }

    function testIsPort(uint node) external pure returns (bool) {
        return Nodes.isPort(node);
    }

    function testIsGuard(uint node) external pure returns (bool) {
        return Nodes.isGuard(node);
    }

    function testIsEvmNode(uint node) external pure returns (bool) {
        return Nodes.isEvm(node);
    }

    function testIsOpaqueNode(uint node) external pure returns (bool) {
        return Nodes.isOpaque(node);
    }

    function testIsLocalNode(uint node) external view returns (bool) {
        return Nodes.isLocal(node);
    }

    function testHostNode(uint value) external pure returns (uint) {
        return Nodes.host(value);
    }

    function testCommandNode(uint value) external pure returns (uint) {
        return Nodes.command(value);
    }

    function testPortNode(uint value) external pure returns (uint) {
        return Nodes.port(value);
    }

    function testGuardNode(uint value) external pure returns (uint) {
        return Nodes.guard(value);
    }

    function testEvmNode(uint value) external pure returns (uint) {
        return Nodes.evm(value);
    }

    function testOpaqueNode(uint value) external pure returns (uint) {
        return Nodes.opaque(value);
    }

    function testToKeccakNode(bytes memory preimage) external pure returns (uint) {
        return Nodes.toKeccak(preimage);
    }

    function testMatchKeccakNode(uint node, bytes memory preimage) external pure returns (uint) {
        return Nodes.matchKeccak(node, preimage);
    }

    function testLocalNode(uint value) external view returns (uint) {
        return Nodes.local(value);
    }

    function testAddr(uint node) external view returns (address) {
        return Nodes.addr(node);
    }

    function testDecodeNode(uint node) external view returns (bytes4, address) {
        return Nodes.decode(node);
    }

    function testLocalHostAddr(uint host) external view returns (address) {
        return Nodes.hostAddr(host);
    }

    function testEnsureHost(uint value, address target) external view returns (uint) {
        return Nodes.matchHost(value, target);
    }

    function testApplyBps(uint amount, uint16 bps) external pure returns (uint) {
        return applyBps(amount, bps);
    }

    function testBeforeBps(uint amount, uint16 bps) external pure returns (uint) {
        return beforeBps(amount, bps);
    }

    function testIsFamily(uint value, uint16 family) external pure returns (bool) {
        return isFamily(value, family);
    }

    function testMatchesBase(bytes32 value, uint base) external pure returns (bool) {
        return matchesBase(value, base);
    }

    function testToLocalBase(uint32 prefix) external view returns (uint) {
        return toLocalBase(prefix);
    }

    function testValueTransaction(
        uint remaining,
        bytes32 account
    ) external returns (uint credit, uint remainingAfter) {
        Execution memory exec;
        exec.account = account;
        exec.budget = remaining;
        (, credit) = exec.close();
        remainingAfter = exec.budget;
    }

    function testAddToBudgetAndClose(
        uint remaining,
        uint extraCredit
    ) external pure returns (uint credit, uint remainingAfter) {
        Execution memory exec;
        exec.budget = remaining;
        exec.addToBudget(extraCredit);
        (, credit) = exec.close();
        remainingAfter = exec.budget;
    }

    function testBytes32ToString(bytes32 value) external pure returns (string memory) {
        return bytes32ToString(value);
    }

    function testMax8(uint value) external pure returns (uint) {
        return max8(value);
    }

    function testMax16(uint value) external pure returns (uint) {
        return max16(value);
    }

    function testMax32(uint value) external pure returns (uint) {
        return max32(value);
    }

    function testClear32(uint value, uint shift) external pure returns (uint) {
        return clear32(value, shift);
    }

    function testClear8(uint value, uint shift) external pure returns (uint) {
        return clear8(value, shift);
    }

    function testClear16(uint value, uint shift) external pure returns (uint) {
        return clear16(value, shift);
    }

    function testClear64(uint value, uint shift) external pure returns (uint) {
        return clear64(value, shift);
    }

    function testReplace8(uint value, uint shift, uint field) external pure returns (uint) {
        return replace8(value, shift, field);
    }

    function testReplace16(uint value, uint shift, uint field) external pure returns (uint) {
        return replace16(value, shift, field);
    }

    function testReplace32(uint value, uint shift, uint field) external pure returns (uint) {
        return replace32(value, shift, field);
    }

    function testReplace64(uint value, uint shift, uint field) external pure returns (uint) {
        return replace64(value, shift, field);
    }

    function testMax64(uint value) external pure returns (uint) {
        return max64(value);
    }

    function testMax128(uint value) external pure returns (uint) {
        return max128(value);
    }

    function testMax160(uint value) external pure returns (uint) {
        return max160(value);
    }
}



