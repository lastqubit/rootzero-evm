// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, GroupsAnnot} from "../Commands.sol";
import {Runtime} from "../core/Runtime.sol";
import {Specs} from "../codec/Specs.sol";
import {Schemas} from "../codec/Schema.sol";

contract TestGroupsAnnotation is CommandBase, GroupsAnnot {
    uint public immutable commandId;
    uint public immutable descriptor;

    constructor(string memory description) Runtime(0) {
        (commandId, descriptor) = command("grouped", Specs.Balance, Specs.Empty, Specs.Position, 0);
        annotateGroups(commandId, description);
    }

    function publish(string memory description) external { annotateGroups(commandId, description); }
    function catalog() external pure returns (uint spec, string memory body) { return (Specs.Groups, Schemas.Groups); }
    function enforceCaller(address caller) internal pure override returns (address) { return caller; }
}
