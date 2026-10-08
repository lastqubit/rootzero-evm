// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

// Aggregator: re-exports the types and helpers needed to author commands.
// Import this file for both standard Execution-based commands and custom decoders.

import {CounterpartyAnnot} from "./annotations/Counterparty.sol";
import {SchemaAnnot} from "./annotations/Schema.sol";
import {GroupsAnnot} from "./annotations/Groups.sol";
import {CommandBase} from "./commands/Base.sol";
import {Flags} from "./utils/Flags.sol";
import {Execution, Executions} from "./execution/Execution.sol";
import {Blocks} from "./codec/Blocks.sol";
import {Sizes, Specs} from "./codec/Specs.sol";
import {Headers} from "./codec/Headers.sol";
import {Cursors} from "./utils/Cursors.sol";
import {AssetAmount, AssetLiability, AccountAsset, HostAsset, AccountBalance, AccountAmount, HostAmount, HostAccountAsset, HostAccountAmount, BalanceConstraints, PositionConstraints, Quote, Position, Tx} from "./core/Types.sol";

// Shared protocol errors.
import {
    InsufficientValue,
    InvalidAccount,
    InvalidAsset,
    InvalidBlock,
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
