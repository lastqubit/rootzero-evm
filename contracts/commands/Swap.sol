// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Execution, Executions, Specs} from "./Base.sol";
import {Position} from "../core/Types.sol";
import {ActionAnnot} from "../annotations/Action.sol";
import {Actions} from "../utils/Actions.sol";

using Executions for Execution;

/// @notice Hook implemented by hosts that swap an exact input amount.
abstract contract SwapExactInHook {
    /// @notice Swap an exact input quantity along a forward asset route.
    /// @dev Called once per SWAP input. The wrapper validates the SWAP container and
    /// LIST framing; the implementation validates the quantity and ASSET stream and
    /// defines supported routes, pools, fees, and settlement. The wrapper returns
    /// the position unchanged; subsequent position-constraint commands enforce limits.
    /// @param liability Input asset to pay.
    /// @param debt Exact quantity of liability to pay.
    /// @param hopsCur Calldata cursor over the LIST payload, excluding its header.
    /// ASSET blocks run forward from liability toward the output asset, excluding
    /// the initial liability; the final hop identifies the output asset.
    /// @return position Complete swap result: asset/amount identify the output and
    /// net quantity received; liability/debt identify the input and exact quantity
    /// paid or owed. The implementation supplies the settlement counterparty.
    function swapExactIn(
        bytes32 liability,
        uint debt,
        uint hopsCur
    ) internal virtual returns (Position memory position);
}

/// @notice Hook implemented by hosts that swap for an exact output amount.
abstract contract SwapExactOutHook {
    /// @notice Obtain an exact output quantity along a reverse asset route.
    /// @dev Called once per SWAP input. The wrapper validates the SWAP container and
    /// LIST framing; the implementation validates the quantity and ASSET stream and
    /// defines supported routes, pools, fees, and settlement. The wrapper returns
    /// the position unchanged; subsequent position-constraint commands enforce limits.
    /// @param asset Desired output asset.
    /// @param amount Exact quantity of asset to receive.
    /// @param hopsCur Calldata cursor over the LIST payload, excluding its header.
    /// ASSET blocks run backward from asset toward the input liability, excluding
    /// the initial output asset; the final hop identifies the input liability.
    /// @return position Complete swap result: asset/amount identify the requested
    /// output and exact quantity received; liability/debt identify the input and
    /// total quantity paid or owed. The implementation supplies the settlement counterparty.
    function swapExactOut(bytes32 asset, uint amount, uint hopsCur) internal virtual returns (Position memory position);
}

/// @notice Swap each SWAP input's exact input amount and return one POSITION per item.
abstract contract SwapExactIn is CommandBase, SwapExactInHook, ActionAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("swapExactIn", Specs.Empty, Specs.Swap, Specs.Position, 0);
        annotateAction(id, Actions.Swap);
    }

    /// @notice Process a SWAP batch with empty state; empty input is a valid empty batch.
    /// @return POSITION blocks returned by the host hook, in input order.
    /// @return Zero native budget credit.
    function swapExactIn(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, swapExactInOne);
    }

    function swapExactInOne(Execution memory exec) private {
        (bytes32 liability, uint debt, uint hopsCur) = exec.unpackSwap();
        Position memory position = swapExactIn(liability, debt, hopsCur);
        exec.outputPosition(position);
    }
}

/// @notice Swap for each SWAP input's exact output amount and return one POSITION per item.
abstract contract SwapExactOut is CommandBase, SwapExactOutHook, ActionAnnot {
    uint private immutable descriptor;

    constructor() {
        uint id;
        (id, descriptor) = command("swapExactOut", Specs.Empty, Specs.Swap, Specs.Position, 0);
        annotateAction(id, Actions.Swap);
    }

    /// @notice Process a SWAP batch with empty state; hops run from output toward input.
    /// @return POSITION blocks returned by the host hook, in input order.
    /// @return Zero native budget credit.
    function swapExactOut(bytes calldata context) external onlyCommand returns (bytes memory, uint) {
        return runCommand(context, descriptor, swapExactOutOne);
    }

    function swapExactOutOne(Execution memory exec) private {
        (bytes32 asset, uint amount, uint hopsCur) = exec.unpackSwap();
        Position memory position = swapExactOut(asset, amount, hopsCur);
        exec.outputPosition(position);
    }
}
