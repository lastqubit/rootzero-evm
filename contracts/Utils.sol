// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

// Aggregator: re-exports protocol identifier, asset, account, cryptographic,
// layout, and general-purpose utility helpers.
// Import this file to access the full utility surface without managing individual paths.

import { Accounts } from "./utils/Accounts.sol";
import { Actions } from "./utils/Actions.sol";
import { Amounts, Assets } from "./utils/Assets.sol";
import { Cur, Cursors } from "./utils/Cursors.sol";
import { ECDSA } from "./utils/ECDSA.sol";
import { Fees } from "./utils/Fees.sol";
import { Ids } from "./utils/Ids.sol";
import { Nodes } from "./utils/Nodes.sol";
import { Positions } from "./utils/Positions.sol";
import { Layout } from "./utils/Layout.sol";
import { Flags } from "./utils/Flags.sol";
import { addrOr, applyBps, beforeBps, bytes32ToInt, bytes32ToString, clear8, clear16, clear32, clear64, divisible, ensureAddr, ensureContract, hash32, intToBytes32, isFamily, matchesBase, MAX_BPS, max8, max16, max24, max32, max40, max64, max96, max128, max160, replace8, replace16, replace32, replace64, retryTicket, toLocalBase, toUnspecifiedBase } from "./utils/Utils.sol";

// Shared protocol errors.
import {
    InsufficientValue,
    InvalidAccount,
    InvalidAsset,
    InvalidContract,
    InvalidId,
    InvalidPreimage,
    NotDivisible,
    OutOfBounds,
    OutOfRange,
    QueryFailed,
    SendFailed,
    UnauthorizedAsset,
    UnconsumedData,
    UnexpectedAmount,
    UnexpectedInput,
    UnexpectedPosition,
    UnexpectedState,
    UnexpectedValue,
    ValueOverflow,
    ZeroAddress,
    ZeroAmount
} from "./utils/Errors.sol";
