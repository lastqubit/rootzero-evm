// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;
import {AdminBase, Execution, Executions, Specs} from "../commands/admin/Base.sol";
import {PortBase} from "../ports/Base.sol";
import {GuardBase} from "../guards/Base.sol";
import {QueryBase} from "../queries/Base.sol";
import {Runtime} from "../core/Runtime.sol";

contract TestEndpointRunners is AdminBase, PortBase, GuardBase, QueryBase {
    using Executions for Execution;
    uint[7] public ids;
    uint[7] private descriptors;
    event Processed(uint amount);
    error Rejected();
    constructor(uint mask) Runtime(0) {
        uint st = Specs.Balance;
        uint inp = Specs.AssetAmount;
        uint out = Specs.AssetAmount;
        (ids[0], descriptors[0]) = command("batch", st, inp, out, 4 | (mask << 3));
        (ids[1], descriptors[1]) = command("once", st, inp, out, 4 | (mask << 3));
        (ids[2], descriptors[2]) = command("admin", st, inp, out, 4 | (mask << 3));
        (ids[6], descriptors[6]) = command("adminOnce", st, inp, out, 4 | (mask << 3));
        (ids[3], descriptors[3]) = port("peer", inp, out, 4 | ((mask & 6) << 3));
        (ids[4], descriptors[4]) = guard("protect", inp, 4 | ((mask & 2) << 3));
        (ids[5], descriptors[5]) = query("read", Specs.AssetAmount, Specs.AssetAmount);
    }
    function batch(bytes calldata context) external payable returns(bytes memory,uint) {
        return runCommand(ids[0], descriptors[0], context, contextOne);
    }
    function once(bytes calldata context) external payable returns(bytes memory,uint) {
        return runCommandOnce(ids[1], descriptors[1], context, contextOne);
    }
    function admin(bytes calldata context) external payable returns(bytes memory,uint) {
        return runAdmin(ids[2], descriptors[2], context, contextOne);
    }
    function adminOnce(bytes calldata context) external payable returns(bytes memory,uint) {
        return runAdminOnce(ids[6], descriptors[6], context, contextOne);
    }
    function peer(bytes calldata input) external payable onlyPeer returns(bytes memory,uint) {
        return runPort(ids[3], descriptors[3], input, inputOne);
    }
    function attributedPeer(bytes32 account, bytes calldata input) external payable onlyPeer returns(bytes memory,uint) {
        return runPort(ids[3], descriptors[3], account, input, inputOne);
    }
    function protect(bytes calldata input) external onlyGuardian {
        runGuard(ids[4], descriptors[4], input, guardOne);
    }
    function read(bytes calldata input) external view returns(bytes memory) {
        return runQuery(descriptors[5], input, readOne);
    }
    function contextOne(Execution memory exec) private {
        exec.unpackBalance();
        inputOne(exec);
    }
    function inputOne(Execution memory exec) private {
        exec.useValue(1);
        readOne(exec);
        emit Processed(1);
    }
    function readOne(Execution memory exec) private pure {
        (bytes32 asset, uint amount) = exec.unpackAssetAmount();
        if(amount == 13) revert Rejected();
        exec.outputAssetAmount(asset, amount * 2);
    }
    function guardOne(Execution memory exec) private {
        (, uint amount) = exec.unpackAssetAmount();
        if(amount == 13) revert Rejected();
        emit Processed(amount);
    }
    function enforceCaller(address who) internal pure override returns(address) { return who; }
    function enforcePeer(address who) internal pure override returns(address) { return who; }
    function enforceAdmin(bytes32 account, address) internal pure override returns(bytes32) {
        if(account == bytes32(0)) revert Rejected();
        return account;
    }
    function enforceCommand(uint) internal pure override returns(bytes4,address) { revert Rejected(); }
    function enforcePort(uint) internal pure override returns(bytes4,address) { revert Rejected(); }
    function setAccess(uint, bool) internal pure override {}
    function appointGuardian(bytes32) internal pure override {}
    function dismissGuardian(bytes32) internal pure override {}
    function enforceGuardian(address who) internal pure override returns(address) { return who; }
}
contract TestQueryCodes is QueryBase {
    constructor(uint inputCodes, uint outputCodes) Runtime(0) {
        query("read", Specs.AssetAmount | inputCodes, Specs.AssetAmount | outputCodes);
    }
}
