// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {Headers as CodecHeaders} from "../Codec.sol";
import {Headers as CommandHeaders} from "../Commands.sol";

import {Quote as CoreQuote} from "../Core.sol";
import {Quote as CodecQuote} from "../Codec.sol";
import {HostAccount} from "../Core.sol";

import {UnexpectedValue} from "../Utils.sol";
import {BookHook} from "../Endpoints.sol";
import {BookHook as CoreBookHook} from "../Core.sol";

// Compile-time coverage for public symbols that were previously omitted from
// their package barrels.
import {
    CommandBase,
    CheckBalance,
    ExecuteCheckBalance,
    CheckPosition,
    ExecuteCheckPosition,
    AllowAsset,
    AllowAssetHook,
    AllowAssetPort,
    DenyAsset,
    DenyAssetHook,
    DenyAssetPort,
    ExecuteCreditAccount,
    ExecuteDebitAccount,
    ExecuteBootstrap,
    Cashout,
    CashinHook,
    CashoutHook,
    SendFailed,
    sendChainAsset,
    ExecuteCashout,
    ExecuteHook as EndpointExecuteHook,
    PipeHook as EndpointPipeHook,
    ExecuteSettle,
    Realize,
    RealizeHook,
    GetBalance,
    GetBalanceHook,
    RequestAssetHook,
    RequestAssetPort,
    RequestAllowancePort,
    BookPort,
    PortPipePayableSelector,
    RevokeAllowance,
    RevokeAsset,
    SettlePayable,
    SettlePayableHook
} from "../Endpoints.sol";
import {HostAsset as CodecHostAsset} from "../Codec.sol";
import {AssetLiability as CodecAssetLiability} from "../Codec.sol";
import {Execution as CodecExecution} from "../Codec.sol";
import {Executions as CodecExecutions} from "../Codec.sol";
import {Flags as CodecFlags} from "../Codec.sol";
import {Memory as CodecMemory} from "../Codec.sol";
import {HostAsset as CommandHostAsset} from "../Commands.sol";
import {AssetLiability as CommandAssetLiability} from "../Commands.sol";
import {Execution as CommandExecution} from "../Commands.sol";
import {Executions as CommandExecutions} from "../Commands.sol";
import {Flags as CommandFlags} from "../Commands.sol";
import {HostAsset as CoreHostAsset} from "../Core.sol";
import {AssetLiability as CoreAssetLiability} from "../Core.sol";
import {Balances as CoreBalances} from "../Core.sol";
import {Flags as EndpointFlags} from "../Endpoints.sol";
import {ResolvedEvent, UnresolvedEvent, SettledEvent, ActionEvent} from "../Events.sol";
import {
    AccessDenied,
    CashinHook as CoreCashinHook,
    CashoutHook as CoreCashoutHook,
    SendFailed as CoreSendFailed,
    sendChainAsset as coreSendChainAsset,
    ActionAnnot,
    CounterpartyAnnot,
    LabelAnnot,
    SchemaAnnot,
    CommandAccess,
    ExecuteHook as CoreExecuteHook,
    PipeHook as CorePipeHook,
    enforceSender,
    InputEndpointBase,
    PortAccess,
    UnexpectedAmount as CoreUnexpectedAmount,
    Calls,
    ForwardHook
} from "../Core.sol";
import {
    UnexpectedAmount as UtilsUnexpectedAmount,
    SendFailed as UtilsSendFailed,
    ZeroAddress,
    clear8,
    clear16,
    clear32,
    clear64,
    ensureAddr,
    replace8,
    replace16,
    replace32,
    replace64
} from "../Utils.sol";

// All shared errors are available through every authoring entry point.
import {
    InsufficientValue as CoreSharedInsufficientValue,
    InvalidAccount as CoreSharedInvalidAccount,
    InvalidAsset as CoreSharedInvalidAsset,
    InvalidContract as CoreSharedInvalidContract,
    InvalidId as CoreSharedInvalidId,
    InvalidPreimage as CoreSharedInvalidPreimage,
    NotDivisible as CoreSharedNotDivisible,
    OutOfBounds as CoreSharedOutOfBounds,
    OutOfRange as CoreSharedOutOfRange,
    QueryFailed as CoreSharedQueryFailed,
    SendFailed as CoreSharedSendFailed,
    UnauthorizedAsset as CoreSharedUnauthorizedAsset,
    UnconsumedData as CoreSharedUnconsumedData,
    UnexpectedAmount as CoreSharedUnexpectedAmount,
    UnexpectedInput as CoreSharedUnexpectedInput,
    UnexpectedPosition as CoreSharedUnexpectedPosition,
    UnexpectedState as CoreSharedUnexpectedState,
    UnexpectedValue as CoreSharedUnexpectedValue,
    ValueOverflow as CoreSharedValueOverflow,
    ZeroAddress as CoreSharedZeroAddress,
    ZeroAmount as CoreSharedZeroAmount
} from "../Core.sol";
import {
    InsufficientValue as CommandsSharedInsufficientValue,
    InvalidAccount as CommandsSharedInvalidAccount,
    InvalidAsset as CommandsSharedInvalidAsset,
    InvalidContract as CommandsSharedInvalidContract,
    InvalidId as CommandsSharedInvalidId,
    InvalidPreimage as CommandsSharedInvalidPreimage,
    NotDivisible as CommandsSharedNotDivisible,
    OutOfBounds as CommandsSharedOutOfBounds,
    OutOfRange as CommandsSharedOutOfRange,
    QueryFailed as CommandsSharedQueryFailed,
    SendFailed as CommandsSharedSendFailed,
    UnauthorizedAsset as CommandsSharedUnauthorizedAsset,
    UnconsumedData as CommandsSharedUnconsumedData,
    UnexpectedAmount as CommandsSharedUnexpectedAmount,
    UnexpectedInput as CommandsSharedUnexpectedInput,
    UnexpectedPosition as CommandsSharedUnexpectedPosition,
    UnexpectedState as CommandsSharedUnexpectedState,
    UnexpectedValue as CommandsSharedUnexpectedValue,
    ValueOverflow as CommandsSharedValueOverflow,
    ZeroAddress as CommandsSharedZeroAddress,
    ZeroAmount as CommandsSharedZeroAmount
} from "../Commands.sol";
import {
    InsufficientValue as EndpointsSharedInsufficientValue,
    InvalidAccount as EndpointsSharedInvalidAccount,
    InvalidAsset as EndpointsSharedInvalidAsset,
    InvalidContract as EndpointsSharedInvalidContract,
    InvalidId as EndpointsSharedInvalidId,
    InvalidPreimage as EndpointsSharedInvalidPreimage,
    NotDivisible as EndpointsSharedNotDivisible,
    OutOfBounds as EndpointsSharedOutOfBounds,
    OutOfRange as EndpointsSharedOutOfRange,
    QueryFailed as EndpointsSharedQueryFailed,
    SendFailed as EndpointsSharedSendFailed,
    UnauthorizedAsset as EndpointsSharedUnauthorizedAsset,
    UnconsumedData as EndpointsSharedUnconsumedData,
    UnexpectedAmount as EndpointsSharedUnexpectedAmount,
    UnexpectedInput as EndpointsSharedUnexpectedInput,
    UnexpectedPosition as EndpointsSharedUnexpectedPosition,
    UnexpectedState as EndpointsSharedUnexpectedState,
    UnexpectedValue as EndpointsSharedUnexpectedValue,
    ValueOverflow as EndpointsSharedValueOverflow,
    ZeroAddress as EndpointsSharedZeroAddress,
    ZeroAmount as EndpointsSharedZeroAmount
} from "../Endpoints.sol";
import {
    InsufficientValue as UtilsSharedInsufficientValue,
    InvalidAccount as UtilsSharedInvalidAccount,
    InvalidAsset as UtilsSharedInvalidAsset,
    InvalidContract as UtilsSharedInvalidContract,
    InvalidId as UtilsSharedInvalidId,
    InvalidPreimage as UtilsSharedInvalidPreimage,
    NotDivisible as UtilsSharedNotDivisible,
    OutOfBounds as UtilsSharedOutOfBounds,
    OutOfRange as UtilsSharedOutOfRange,
    QueryFailed as UtilsSharedQueryFailed,
    SendFailed as UtilsSharedSendFailed,
    UnauthorizedAsset as UtilsSharedUnauthorizedAsset,
    UnconsumedData as UtilsSharedUnconsumedData,
    UnexpectedAmount as UtilsSharedUnexpectedAmount,
    UnexpectedInput as UtilsSharedUnexpectedInput,
    UnexpectedPosition as UtilsSharedUnexpectedPosition,
    UnexpectedState as UtilsSharedUnexpectedState,
    UnexpectedValue as UtilsSharedUnexpectedValue,
    ValueOverflow as UtilsSharedValueOverflow,
    ZeroAddress as UtilsSharedZeroAddress,
    ZeroAmount as UtilsSharedZeroAmount
} from "../Utils.sol";

import {Quote as CommandQuote, ActionAnnot as CommandActionAnnot, CounterpartyAnnot as CommandCounterpartyAnnot, LabelAnnot as CommandLabelAnnot, SchemaAnnot as CommandSchemaAnnot} from "../Commands.sol";
import {Cur as UtilsCur, Cursors as UtilsCursors} from "../Utils.sol";
