// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/**
 * @dev Extension of {ERC20Upgradeable} that allows to implement a blocklist
 * mechanism that can be managed by an authorized account with the
 * {_blockUser} and {_unblockUser} functions.
 *
 * The blocklist provides the guarantee to the contract owner
 * (e.g. a DAO or a well-configured multisig) that any account won't be
 * able to execute transfers or approvals to other entities to operate
 * on its behalf if {_blockUser} was not called with such account as an
 * argument. Similarly, the account will be unblocked again if
 * {_unblockUser} is called.
 */
abstract contract WG25_Blocklist is ERC20Upgradeable {
    /// @dev Sentinel `blockedUntil` value meaning the block never expires.
    uint256 internal constant BLOCKED_PERMANENT = type(uint256).max;

    /// @custom:storage-location erc7201:WG25_Blocklist.storage
    struct ERC20BlocklistUpgradeableStorage {
        /**
         * @dev Timestamp until which an address is blocked. A user is blocked while
         * `block.timestamp < _blockedUntil[user]`. Zero means not blocked;
         * {BLOCKED_PERMANENT} means blocked indefinitely.
         */
        mapping(address user => uint256 blockedUntil) _blockedUntil;
    }

    // keccak256(abi.encode(uint256(keccak256("WG25_Blocklist.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20BlocklistUpgradeableStorageLocation =
        0x943d6f0aae33a11bdac5b1e1fa272eeefbfbb201792466fc6e6bfcdac78e2f00;

    function _getERC20BlocklistStorage() private pure returns (ERC20BlocklistUpgradeableStorage storage $) {
        assembly {
            $.slot := ERC20BlocklistUpgradeableStorageLocation
        }
    }

    /**
     * @dev Emitted when a user is blocked until the `blockedUntil` timestamp
     * ({BLOCKED_PERMANENT} for an indefinite block).
     */
    event UserBlocked(address indexed user, uint256 blockedUntil);

    /**
     * @dev Emitted when a user is unblocked.
     */
    event UserUnblocked(address indexed user);

    /**
     * @dev The operation failed because the user is blocked.
     */
    error ERC20Blocked(address user);

    /**
     * @dev The zero address cannot be added to the blocklist. Blocking it would
     * brick minting (`_update(address(0), to)`) and burning (`_update(from, address(0))`).
     */
    error ERC20BlocklistInvalidUser(address user);

    /**
     * @dev A block must expire in the future; `blockedUntil` was not after the current time.
     */
    error ERC20BlocklistInvalidUntil(uint256 blockedUntil);

    /**
     * @dev Returns true while the account is blocked, i.e. until its {blockedUntil} timestamp.
     */
    function blocked(address account) public view virtual returns (bool) {
        return block.timestamp < _getERC20BlocklistStorage()._blockedUntil[account];
    }

    /**
     * @dev Returns the timestamp until which `account` is blocked (0 if not blocked,
     * {BLOCKED_PERMANENT} if blocked indefinitely). Note the value may lie in the past
     * for an expired block; use {blocked} for the current status.
     */
    function blockedUntil(address account) public view virtual returns (uint256) {
        return _getERC20BlocklistStorage()._blockedUntil[account];
    }

    /**
     * @dev Blocks a user from sending, receiving, and being approved as a spender until the
     * `until` timestamp. Pass {BLOCKED_PERMANENT} for an indefinite block. Reverts if `until`
     * is not in the future. Calling again overwrites the previous expiry (extend or shorten).
     */
    function _blockUser(address user, uint256 until) internal virtual {
        if (user == address(0)) revert ERC20BlocklistInvalidUser(address(0));
        if (until <= block.timestamp) revert ERC20BlocklistInvalidUntil(until);
        _getERC20BlocklistStorage()._blockedUntil[user] = until;
        emit UserBlocked(user, until);
    }

    /**
     * @dev Unblocks a user immediately, before any scheduled expiry.
     */
    function _unblockUser(address user) internal virtual {
        _getERC20BlocklistStorage()._blockedUntil[user] = 0;
        emit UserUnblocked(user);
    }

    /**
     * @dev See {ERC20-_update}.
     *
     * A blocked account cannot send (`from`) or receive (`to`) tokens via transfers.
     * Burns (`to == address(0)`) are intentionally allowed even when `from` is blocked
     * so an authorized role can destroy/seize a blocked account's balance, and mints
     * (`from == address(0)`) are allowed to a blocked recipient so an authorized role
     * can credit an account whose funds then remain frozen until it is unblocked.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (to != address(0) && blocked(from)) revert ERC20Blocked(from);
        if (from != address(0) && blocked(to)) revert ERC20Blocked(to);
        super._update(from, to, value);
    }

    /**
     * @dev See {ERC20-_approve}.
     *
     * Neither the `owner` nor the `spender` may be blocked when granting a non-zero
     * allowance. Revoking an allowance (`value == 0`) to an already-blocked spender is
     * still permitted so owners can clean up stale approvals.
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual override {
        if (blocked(owner)) revert ERC20Blocked(owner);
        if (value != 0 && blocked(spender)) revert ERC20Blocked(spender);
        super._approve(owner, spender, value, emitEvent);
    }
}
