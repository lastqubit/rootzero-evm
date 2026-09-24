// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

// Aggregator: re-exports command, admin, port, guard, and query endpoint abstractions.
// Import this file to inherit from the full rootzero callable host surface without managing individual paths.

// Shared endpoint hooks
import {CashinHook, CashoutHook, sendChainAsset} from "./core/Cash.sol";
import {Flags} from "./utils/Flags.sol";
import {ExecuteHook, PipeHook} from "./core/Pipeline.sol";
import {BookHook, CreditAccountHook, DebitAccountHook, RepayHook, SettleHook} from "./core/Settlement.sol";

// Commands
import {CommandBase} from "./commands/Base.sol";
import {Allocate, AllocateHook} from "./commands/Allocate.sol";
import {CheckBalance, ExecuteCheckBalance} from "./commands/Balance.sol";
import {Burn, BurnHook} from "./commands/Burn.sol";
import {ExecuteBootstrap} from "./commands/Bootstrap.sol";
import {Cashout, ExecuteCashout} from "./commands/Cashout.sol";
import {CreditAccount, ExecuteCreditAccount} from "./commands/Credit.sol";
import {DebitAccount, ExecuteDebitAccount} from "./commands/Debit.sol";
import {Deposit, DepositHook, DepositPayable, DepositPayableHook} from "./commands/Deposit.sol";
import {Payout, PayoutHook} from "./commands/Payout.sol";
import {CheckPosition, ExecuteCheckPosition} from "./commands/Position.sol";
import {Provision, ProvisionHook, ProvisionPayable, ProvisionPayableHook} from "./commands/Provision.sol";
import {RecoverPayable, RecoverPayableHook} from "./commands/Recover.sol";
import {Realize, RealizeHook} from "./commands/Realize.sol";
import {Repay} from "./commands/Repay.sol";
import {RelayPayable, RelayBalancePayable, RelayPayableHook} from "./commands/Relay.sol";
import {Settle, SettlePayable, SettlePayableHook, ExecuteSettle} from "./commands/Settle.sol";
import {Withdraw, WithdrawHook} from "./commands/Withdraw.sol";

// Admin commands
import {AdminBase} from "./commands/admin/Base.sol";
import {AllowAsset, AllowAssetHook, DenyAsset, DenyAssetHook} from "./commands/admin/Asset.sol";
import {Allowance, AllowanceHook} from "./commands/admin/Allowance.sol";
import {Annotate} from "./commands/admin/Annotate.sol";
import {Appoint, Dismiss} from "./commands/admin/Guardian.sol";
import {Authorize, ExecuteAuthorize} from "./commands/admin/Authorize.sol";
import {ExecutePayable} from "./commands/admin/Execute.sol";
import {Unauthorize} from "./commands/admin/Unauthorize.sol";

// Port endpoints
import {PortBase} from "./ports/Base.sol";
import {AllowAssetPort, DenyAssetPort, RequestAssetPort, RequestAssetHook} from "./ports/Asset.sol";
import {RequestAllowancePort} from "./ports/Allowance.sol";
import {CreditAccountPort} from "./ports/Credit.sol";
import {BookPort} from "./ports/Book.sol";
import {DebitAccountPort} from "./ports/Debit.sol";
import {PipePayablePort, PortPipePayableSelector} from "./ports/Pipe.sol";
import {DispatchPayablePort, DispatchPayableHook} from "./ports/Dispatch.sol";

// Guard endpoints
import {GuardBase} from "./guards/Base.sol";
import {Revoke, RevokeAllowance, RevokeAsset} from "./guards/Revoke.sol";

// Query endpoints
import {QueryBase} from "./queries/Base.sol";
import {AssetStatus, AssetStatusHook} from "./queries/Asset.sol";
import {GetBalance, GetBalanceHook} from "./queries/Balance.sol";

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
