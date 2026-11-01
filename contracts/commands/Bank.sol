// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {CommandBase, Specs} from "./Base.sol";
import {Execute} from "../codec/Execute.sol";
import {Sizes} from "../codec/Specs.sol";
import {CreditAccountHook} from "../core/Settlement.sol";
import {Cursors} from "../utils/Cursors.sol";
import {UnexpectedInput} from "../utils/Errors.sol";

/// @title ExecuteBank
/// @notice Pipeline-local sink that keeps BALANCE state on the account's ledger.
/// @dev The commander's counterpart of `bootstrap`. Hosts that want an external
/// credit command use `CreditAccount` instead.
abstract contract ExecuteBank is CommandBase, CreditAccountHook {
    uint private immutable id;

    constructor() {
        (id, ) = command("bank", Specs.Balance, Specs.Empty, Specs.Empty, 0);
    }

    /// @notice Return the registered BANK command ID.
    /// @return Registered command node identifier.
    function bankId() internal view returns (uint) {
        return id;
    }

    /// @notice Credit each BALANCE block from pipeline state to the account.
    /// @param account Account credited by each balance.
    /// @param state BALANCE block stream held in pipeline memory.
    /// @param inputCur Cursor over empty input required by the command schema.
    /// @param value Native value assigned to the command; returned unused as credit.
    /// @return handled Always true because this helper executed the command.
    /// @return output Empty output state.
    /// @return credit Unused assigned native value.
    function executeBank(
        bytes32 account,
        bytes memory state,
        uint inputCur,
        uint value
    ) internal returns (bool handled, bytes memory output, uint credit) {
        if (!Cursors.done(inputCur)) revert UnexpectedInput();
        (uint abs, uint end) = Execute.bounds(state, Sizes.Balance);

        while (abs < end) {
            (bytes32 asset, uint amount) = Execute.unpackBalanceMemory(abs);
            creditAccount(account, asset, amount);
            unchecked {
                abs += Sizes.Balance;
            }
        }

        // The default output is the shared empty bytes value; no allocation is needed.
        return (true, output, value);
    }
}
