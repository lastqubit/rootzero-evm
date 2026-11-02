// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Specs} from "../codec/Specs.sol";
import {Variants} from "../codec/Variants.sol";
import {Executions} from "../execution/Execution.sol";
import {Specs as CodecSpecs, Variants as CodecVariants} from "../Codec.sol";
import {Variants as CommandVariants} from "../Commands.sol";
import {TestSettleCommand} from "./TestSettleCommand.sol";
import {TestPoolCommands} from "./TestPoolCommands.sol";
import {TestSwapCommands} from "./TestSwapCommands.sol";

/// @dev Exposes spec variant packing and the protocol variant constants.
contract TestLaneVariants {
    function toVariant(uint spec, bytes4 variantKey) external pure returns (uint) {
        return Specs.toVariant(spec, variantKey);
    }

    function variant(uint spec) external pure returns (bytes4) {
        return Specs.variant(spec);
    }

    function toLane(uint spec, uint32 laneKey) external pure returns (uint) {
        return Specs.toLane(spec, laneKey);
    }

    function laneThenVariant(uint spec, uint32 laneKey, bytes4 variantKey) external pure returns (uint) {
        return Specs.toVariant(Specs.toLane(spec, laneKey), variantKey);
    }

    function variantThenLane(uint spec, bytes4 variantKey, uint32 laneKey) external pure returns (uint) {
        return Specs.toLane(Specs.toVariant(spec, variantKey), laneKey);
    }

    function describe(uint state, uint input, uint output) external pure returns (uint) {
        return Executions.describe(state, input, output);
    }

    function keys() external pure returns (bytes4[8] memory) {
        return [
            Variants.Debt, Variants.Counterparty, Variants.Ledger, Variants.Same,
            Variants.Realized, Variants.Repaid, Variants.NewAsset, Variants.NewDebt
        ];
    }

    function specs() external pure returns (uint[8] memory) {
        return [
            Specs.PositionDebt, Specs.PositionCounterparty, Specs.PositionLedger, Specs.PositionSame,
            Specs.PositionRealized, Specs.PositionRepaid, Specs.PositionNewAsset, Specs.PositionNewDebt
        ];
    }

    function plain() external pure returns (uint position, uint counterparty) {
        return (Specs.Position, Specs.Counterparty);
    }

    function barrels() external pure returns (bytes4, bytes4, uint) {
        return (CodecVariants.Debt, CommandVariants.NewDebt, CodecSpecs.PositionNewDebt);
    }
}

/// @dev Settle host that declares a counterparty-only state lane through the hook.
contract TestSettleStateVariant is TestSettleCommand {
    function settleState() internal pure override returns (uint) {
        return Specs.PositionCounterparty;
    }
}

/// @dev Pool host that adds a variant to the inherited, described addPool input lane.
contract TestPoolInputVariant is TestPoolCommands {
    bytes4 public constant VARIANT = bytes4(keccak256("assetAmount.test"));

    constructor(uint commander) TestPoolCommands(commander) {}

    function addPoolInput() internal override returns (uint) {
        return Specs.toVariant(super.addPoolInput(), VARIANT);
    }
}

/// @dev Swap host that declares counterparty-bearing outputs, as a configured AMM would.
contract TestSwapOutputVariant is TestSwapCommands {
    constructor(uint commander, bytes32 account) TestSwapCommands(commander, account) {}

    function swapExactInputOutput() internal pure override returns (uint) {
        return Specs.PositionCounterparty;
    }

    function swapExactOutputOutput() internal pure override returns (uint) {
        return Specs.PositionCounterparty;
    }
}
