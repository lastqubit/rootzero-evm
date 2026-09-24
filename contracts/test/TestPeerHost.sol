// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {OutOfRange} from "../utils/Errors.sol";

import { Host } from "../core/Host.sol";
import { RequestAllowancePort } from "../ports/Allowance.sol";
import { CreditAccountPort } from "../ports/Credit.sol";
import { DebitAccountPort } from "../ports/Debit.sol";
import { PipePayablePort } from "../ports/Pipe.sol";
import { DispatchPayablePort } from "../ports/Dispatch.sol";
import { BookPort } from "../ports/Book.sol";
import { RequestAssetPort } from "../ports/Asset.sol";
import { Settlement } from "../core/Settlement.sol";
import { Pipeline } from "../core/Pipeline.sol";
import { Position } from "../core/Types.sol";
import { Execution } from "../execution/Execution.sol";

contract TestPortHost is Host, Settlement, Pipeline, RequestAllowancePort, CreditAccountPort, DebitAccountPort, BookPort, RequestAssetPort, PipePayablePort, DispatchPayablePort {
    event PortRequestAllowanceCalled(uint peer, bytes32 asset, uint amount);
    event PortDebitAccountCalled(bytes32 account, bytes32 asset, uint amount);
    event PortCreditAccountCalled(bytes32 account, bytes32 asset, uint amount);
    event PortDispatchCalled(uint portal, bytes payload, uint resources, uint remaining);
    event PortRequestAssetCalled(uint peer, bytes32 asset, uint amount);
    event CashinCalled(bytes32 account, uint amount);
    constructor(uint cmdr) Host(cmdr) {}

    function cashin(bytes32 account, uint amount) internal override {
        emit CashinCalled(account, amount);
    }

    /// @notice Test-only helper for invoking commands on a host commanded by this contract.
    function testCall(address target, bytes calldata data) external payable returns (bytes memory out) {
        bool success;
        (success, out) = target.call{value: msg.value}(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(out, 0x20), mload(out))
            }
        }
    }

    function allowance(uint peer, bytes32 asset, uint amount) internal override {
        emit PortRequestAllowanceCalled(peer, asset, amount);
    }

    function requestAsset(uint peer, bytes32 asset, uint amount) internal override {
        emit PortRequestAssetCalled(peer, asset, amount);
    }

    function debitAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        emit PortDebitAccountCalled(account, asset, amount);
    }

    function creditAccount(bytes32 account, bytes32 asset, uint amount) internal override {
        emit PortCreditAccountCalled(account, asset, amount);
    }

    function testSettle(bytes32 account, Position calldata position) external {
        if (position.debt > type(uint128).max) revert OutOfRange();
        settle(account, position);
    }


    function dispatchTo(uint portal, uint resources, bytes memory payload, Execution memory funds) internal override {
        emit PortDispatchCalled(portal, payload, resources, funds.budget);
    }

    function execute(
        uint,
        bytes32,
        bytes memory state,
        bytes calldata,
        uint
    ) internal pure override returns (bool handled, bytes memory nextState, uint returnedCredit) {
        return (false, state, 0);
    }

    function getAdminAccount() external view returns (bytes32) { return admin; }
}



