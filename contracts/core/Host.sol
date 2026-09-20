// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {AccessDenied, CallerAccess} from "./Access.sol";
import {Runtime} from "./Runtime.sol";
import {Annotate} from "../commands/admin/Annotate.sol";
import {Appoint, Dismiss} from "../commands/admin/Guardian.sol";
import {Authorize} from "../commands/admin/Authorize.sol";
import {Unauthorize} from "../commands/admin/Unauthorize.sol";
import {ExecutePayable} from "../commands/admin/Execute.sol";
import {Revoke} from "../guards/Revoke.sol";
import {IntroductionEvent} from "../events/Introduction.sol";
import {GuardianEvent} from "../events/Guardian.sol";
import {NodeEvent} from "../events/Node.sol";
import {Accounts} from "../utils/Accounts.sol";
import {Actions} from "../utils/Actions.sol";
import {Nodes} from "../utils/Nodes.sol";

/// @title IHostIntroduction
/// @notice Interface implemented by hosts that accept introductions from other hosts.
interface IHostIntroduction {
    /// @notice Record a host introduction claim.
    /// @param peer Host node ID being introduced.
    /// @param blocknum Block number at which the introduction was made.
    function introduce(uint peer, uint blocknum) external;
}

/// @title HostAnnouncer
/// @notice Shared outbound introduction behavior for rootzero hosts.
/// Calls a deployed commander during construction without adding an inbound
/// introduction endpoint to the inheriting host.
abstract contract HostAnnouncer is Runtime {
    /// @dev Deployment reverts if a contract commander does not accept `introduce(uint,uint)`.
    constructor() {
        if (commander == host) return;
        address target = commanderAddr;
        if (target.code.length == 0) return;
        IHostIntroduction(target).introduce(host, block.number);
    }

    /// @notice Introduce this host to the contract address embedded in a local EVM node ID.
    /// @dev Accepts host and endpoint IDs such as commands, ports, queries, and guards.
    /// Reverts when `node` is not local or embeds the zero address.
    /// @param node Local EVM node ID whose underlying contract receives the introduction.
    function introduceTo(uint node) internal {
        IHostIntroduction(Nodes.addr(node)).introduce(host, block.number);
    }
}

/// @title HostIntroduction
/// @notice Full introduction capability for hosts that both announce themselves
/// to a commander and accept introduction claims from other hosts.
abstract contract HostIntroduction is HostAnnouncer, IntroductionEvent, IHostIntroduction {
    /// @notice Record a host introduction claim.
    /// @dev Validates that `peer` matches `msg.sender`; it does not authorize or trust the introduced host.
    /// @param peer Host node ID being introduced.
    /// @param blocknum Block number at which the host was deployed.
    function introduce(uint peer, uint blocknum) external {
        emit Introduction(host, Nodes.matchHost(peer, msg.sender), Accounts.toUser(tx.origin), blocknum);
    }
}

/// @title CommandHost
/// @notice Minimal host base for commander-only command execution.
/// Does not include admin commands, peer authorization, guardians, inbound
/// introductions, generic execution, or a native-token receive function.
/// Pipelines must separately compose a `CommandAccess` policy.
abstract contract CommandHost is CallerAccess, HostAnnouncer {
    /// @dev Thrown when a commander-only host is deployed without an external commander.
    error InvalidCommander();

    /// @param cmdr Nonzero local host ID allowed to invoke hosted commands.
    constructor(uint cmdr) Runtime(cmdr) {
        if (cmdr == 0) revert InvalidCommander();
    }

    function enforceCaller(address caller) internal view virtual override returns (address) {
        if (caller == address(0) || caller != commanderAddr) revert AccessDenied();
        return caller;
    }
}

/// @title Host
/// @notice Abstract base contract for rootzero host implementations.
/// Inherits admin command support (authorize, unauthorize, label, executePayable),
/// guardian management, the default guardian revoke action, and
/// optionally introduces itself to a commander host at deployment.
/// Accepts native ETH payments via the `receive` function.
abstract contract Host is
    HostIntroduction,
    Annotate,
    Authorize,
    Unauthorize,
    ExecutePayable,
    Appoint,
    Dismiss,
    Revoke,
    NodeEvent,
    GuardianEvent
{
    /// @dev Admin account ID derived from the commander identity.
    bytes32 internal immutable admin;

    /// @dev Explicitly authorized local node IDs.
    mapping(uint node => bool) internal nodes;

    /// @dev Active guardian user accounts.
    mapping(bytes32 account => bool) internal guardians;

    /// @param cmdr Commander host ID; used by the composed access capabilities.
    ///        If the encoded native target is a deployed contract, the host
    ///        calls `introduce` on it during construction.
    constructor(uint cmdr) Runtime(cmdr) {
        admin = Accounts.toAdmin(commanderAddr);
    }

    function authorizeNode(uint node) internal virtual override {
        node = Nodes.local(node);
        nodes[node] = true;
        emit Node(host, node, Actions.Authorize, 1);
    }

    function revokeNode(uint node) internal virtual override {
        node = Nodes.local(node);
        nodes[node] = false;
        emit Node(host, node, Actions.Revoke, 0);
    }

    function appointGuardian(bytes32 account) internal virtual override {
        account = Accounts.user(account);
        guardians[account] = true;
        emit Guardian(host, account, Actions.Appoint, 1);
    }

    function dismissGuardian(bytes32 account) internal virtual override {
        account = Accounts.user(account);
        guardians[account] = false;
        emit Guardian(host, account, Actions.Dismiss, 0);
    }

    /// @notice Return true if `caller` is the commander, this host, or an authorized host.
    function isTrustedCaller(address caller) internal view returns (bool) {
        if (caller == address(0)) return false;
        return caller == commanderAddr || caller == address(this) || nodes[Nodes.toHost(caller)];
    }

    /// @notice Return true if `addr` belongs to an active guardian account.
    function isGuardian(address addr) internal view returns (bool) {
        return guardians[Accounts.toUser(addr)];
    }

    function enforceAdmin(bytes32 account, address caller) internal view virtual override returns (bytes32) {
        if (caller == address(0) || account != admin || caller != commanderAddr) revert AccessDenied();
        return account;
    }

    function enforceGuardian(address caller) internal view virtual override returns (address) {
        if (caller == address(0) || !isGuardian(caller)) revert AccessDenied();
        return caller;
    }

    function enforceCaller(address caller) internal view virtual override returns (address) {
        if (!isTrustedCaller(caller)) revert AccessDenied();
        return caller;
    }

    function enforcePeer(address caller) internal view virtual override returns (address) {
        if (caller == commanderAddr || !isTrustedCaller(caller)) revert AccessDenied();
        return caller;
    }

    function enforceNode(uint node) internal view returns (bytes4 selector, address target) {
        if (!nodes[node]) revert AccessDenied();
        selector = bytes4(uint32(node >> 160));
        target = address(uint160(node));
    }

    function enforceCommand(uint command) internal view virtual override returns (bytes4 selector, address target) {
        return enforceNode(Nodes.command(command));
    }

    function enforcePort(uint port) internal view virtual override returns (bytes4 selector, address target) {
        return enforceNode(Nodes.port(port));
    }

    /// @notice Accept native ETH transfers (e.g. from command value flows).
    receive() external payable {}
}
