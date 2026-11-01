// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.33;

import {TrustCheck} from "./Access.sol";
import {Accounts} from "../utils/Accounts.sol";
import {ECDSA} from "../utils/ECDSA.sol";
import {Nodes} from "../utils/Nodes.sol";

/// @title SignedEntry
/// @notice Verifies a pipeline signed by a secp256k1 key, for a commander's signed entry point.
/// Anyone can submit it, on any chain, as the key's user account of a chosen home chain.
///
/// The signature is EIP-712 over the home chain, steps, native value and deadline, in a domain
/// binding this chain and contract. The deadline is the replay protection: each signature must
/// have a later deadline than the signer's last one here, so a later signature, even an empty
/// pipeline, cancels every earlier one. A reverted pipeline doesn't advance it, so its signature
/// stays usable until it expires or is superseded. Wallets should use a fixed offset from the
/// current time and refuse anything beyond `MAX_WINDOW`: a signature dated further ahead becomes
/// usable later, and can't be cancelled first.
///
/// A home chain must be in the trusted set as its chain node. Only chains that permanently tie
/// an address to its key belong there: with key rotation, an old key could still sign as that
/// chain's account. A commander's relays carry the account to other chains, so a home chain has
/// to be removed on every connected commander to close it.
abstract contract SignedEntry is TrustCheck {
    /// @dev Longest time a deadline can be ahead of the current block, which also limits how long
    /// a signature can block the signer's others.
    uint internal constant MAX_WINDOW = 1 hours;

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("rootzero");
    bytes32 private constant VERSION_HASH = keccak256("1");
    bytes32 private constant PIPELINE_TYPEHASH =
        keccak256("Pipeline(uint256 home,bytes steps,uint256 value,uint256 deadline)");

    /// @dev The domain at deployment, recomputed if a fork changes the chain ID or this runs behind a proxy.
    bytes32 private immutable cachedDomain = domainHash();
    uint private immutable cachedChain = block.chainid;
    address private immutable cachedThis = address(this);

    /// @dev Thrown when the home chain is out of range or not allowed.
    error InvalidHome();
    /// @dev Thrown when a deadline is further ahead than `MAX_WINDOW`.
    error InvalidDeadline();
    /// @dev Thrown when a signature can't be recovered or has a high `s`.
    error InvalidSignature();
    /// @dev Thrown when a deadline isn't later than the signer's last one.
    error NonceUsed();

    /// @notice Highest deadline each signer has used here. A new signature must be later than this.
    mapping(address signer => uint deadline) public lastDeadlines;

    function domainHash() private view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
    }

    /// @dev Digest of a pipeline with the call's `msg.value`.
    function pipelineDigest(uint home, bytes calldata steps, uint deadline) private view returns (bytes32) {
        bytes32 domain = block.chainid == cachedChain && address(this) == cachedThis ? cachedDomain : domainHash();
        bytes32 pipeline = keccak256(abi.encode(PIPELINE_TYPEHASH, home, keccak256(steps), msg.value, deadline));
        return keccak256(abi.encodePacked("\x19\x01", domain, pipeline));
    }

    /// @notice Verify a signed pipeline, record its deadline and return the signer's account of `home`.
    /// @dev A tampered field recovers some other signer, whose account is its own. The caller checks
    /// that the deadline hasn't passed.
    /// @param home Chain ID of the account's chain, allowed as a trusted chain node.
    /// @param steps STEP block stream that was signed.
    /// @param deadline Signed deadline, later than the signer's last and within `MAX_WINDOW`.
    /// @param r Signature `r`.
    /// @param vs EIP-2098 compact signature: y parity in the top bit, `s` below it.
    /// @return User account of the signer on `home`.
    function signedAccount(
        uint home,
        bytes calldata steps,
        uint deadline,
        bytes32 r,
        bytes32 vs
    ) internal returns (bytes32) {
        if (home == 0 || home > type(uint32).max || !isTrusted(Nodes.toChain(home))) revert InvalidHome();
        if (deadline > block.timestamp + MAX_WINDOW) revert InvalidDeadline();

        uint s = uint(vs) & (type(uint).max >> 1);
        if (s > ECDSA.MALLEABILITY_THRESHOLD) revert InvalidSignature();
        address signer = ecrecover(pipelineDigest(home, steps, deadline), uint8(uint(vs) >> 255) + 27, r, bytes32(s));
        if (signer == address(0)) revert InvalidSignature();

        if (deadline <= lastDeadlines[signer]) revert NonceUsed();
        lastDeadlines[signer] = deadline;
        return Accounts.toChainUser(signer, home);
    }
}
