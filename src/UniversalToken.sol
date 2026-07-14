// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20BlocklistUpgradeable} from "./ERC20BlocklistUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract UniversalToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    ERC20BlocklistUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE"); // block/unblock user (usually called LIMITER)

    uint8 private nrOfDecimals;

    /// @dev Thrown when a seizure is attempted against an account that is not blocked.
    error AccountNotBlocked(address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory tokenName, string memory tokenSymbol, uint8 tokenDecimals) public initializer {
        __ERC20_init(tokenName, tokenSymbol);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init(tokenName);

        nrOfDecimals = tokenDecimals;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(FREEZER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    ///////////////////
    // External Functions
    ///////////////////

    /// @notice Wrapps ERC20Upgradeable._mint. Minting to a blocked account is
    /// permitted; the minted tokens stay frozen until the account is unblocked.
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Wrapps ERC20BurnableUpgradeable._burn
    function burn(uint256 value) public override onlyRole(MINTER_ROLE) {
        super.burn(value);
    }

    /// @notice Wrapps ERC20BurnableUpgradeable._burnFrom
    function burnFrom(address account, uint256 value) public override onlyRole(MINTER_ROLE) {
        super.burnFrom(account, value);
    }

    /// @notice Wrapps ERC20PausableUpgradeable._pause
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Wrapps ERC20PausableUpgradeable._unpause
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Blocks a user until the given `blockedUntil` timestamp (a date), after
    /// which the account is automatically unblocked. Reverts if the date is not in the future.
    function blockUser(address user, uint256 blockedUntil) external onlyRole(FREEZER_ROLE) {
        _blockUser(user, blockedUntil);
    }

    /// @notice Blocks a user indefinitely (never auto-expires); lift only via {unblockUser}.
    function blockUserPermanent(address user) external onlyRole(FREEZER_ROLE) {
        _blockUser(user, BLOCKED_PERMANENT);
    }

    /// @notice Wrapps ERC20BlocklistUpgradeable._unblockUser
    function unblockUser(address user) external onlyRole(FREEZER_ROLE) {
        _unblockUser(user);
    }

    /// @notice Seizes and destroys tokens held by a blocked account.
    /// @dev The account must already be blocked (an action performed by a FREEZER),
    /// which enforces a deliberate two-action flow before any balance is destroyed.
    /// Seizure must remain possible during an incident, so this invokes the base ERC20
    /// accounting directly and deliberately bypasses the pause guard in the overridden
    /// `_update` chain (the blocklist guard already permits burns from blocked accounts).
    /// The base `_update` still enforces the balance check (reverts on insufficient funds).
    function forceBurn(address account, uint256 amount) external onlyRole(FREEZER_ROLE) {
        if (!blocked(account)) revert AccountNotBlocked(account);
        ERC20Upgradeable._update(account, address(0), amount);
    }

    /// @inheritdoc ERC20Upgradeable
    function decimals() public view override returns (uint8) {
        return nrOfDecimals;
    }

    /// @inheritdoc ERC20Upgradeable
    /// @dev Also rejects a blocked spender: the blocklist gates `from`/`to` in
    /// {_update}, but the spender (`_msgSender()`) must be checked here to stop a
    /// blocked address from moving a third party's tokens via a pre-existing allowance.
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (blocked(_msgSender())) revert ERC20Blocked(_msgSender());
        return super.transferFrom(from, to, value);
    }

    ///////////////////
    // Internal Functions
    ///////////////////

    /// @inheritdoc	ERC20Upgradeable
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20BlocklistUpgradeable)
    {
        super._update(from, to, value);
    }

    /// @inheritdoc	ERC20Upgradeable
    function _approve(address owner, address spender, uint256 value, bool emitEvent)
        internal
        override(ERC20Upgradeable, ERC20BlocklistUpgradeable)
    {
        super._approve(owner, spender, value, emitEvent);
    }
}
