// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {UniversalToken} from "../src/UniversalToken.sol";
import {ERC20BlocklistUpgradeable} from "../src/ERC20BlocklistUpgradeable.sol";
import {DeployToken} from "../script/DeployToken.s.sol";

/// @dev Regression tests for the blocklist & seizure hardening:
///  - the zero address can never be blocked (mint/burn can never be bricked)
///  - a blocked spender cannot move funds via transferFrom
///  - a non-zero allowance cannot be granted to a blocked spender (incl. permit path)
///  - a FREEZER can seize (force-burn) a blocked account's balance
contract SecurityFixes is Test {
    UniversalToken private token;

    address minter = address(0x3);
    address pauser = address(0x2);
    address freezer = address(0x4);

    uint256 constant ONE = 1e8;

    function setUp() public {
        vm.setEnv("TOKEN_NAME", "Universal Token Test");
        vm.setEnv("TOKEN_SYMBOL", "UTT");
        vm.setEnv("TOKEN_DECIMALS", "8");

        DeployToken deployer = new DeployToken();
        token = deployer.run();

        vm.startPrank(DEFAULT_SENDER);
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.PAUSER_ROLE(), pauser);
        token.grantRole(token.FREEZER_ROLE(), freezer);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // zero address can never be blocked
    // ---------------------------------------------------------------------

    function test_CannotBlockZeroAddress() public {
        vm.prank(freezer);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20BlocklistInvalidUser.selector, address(0))
        );
        token.blockUserPermanent(address(0));

        assertFalse(token.blocked(address(0)));
    }

    function test_MintAndBurnUnaffected() public {
        address user = makeAddr("user");

        // block attempt on zero reverts (above); mint & burn keep working
        vm.prank(minter);
        token.mint(user, 10 * ONE);
        assertEq(token.balanceOf(user), 10 * ONE);

        bytes32 minterRole = token.MINTER_ROLE();
        vm.prank(DEFAULT_SENDER);
        token.grantRole(minterRole, user);

        vm.prank(user);
        token.burn(4 * ONE);
        assertEq(token.balanceOf(user), 6 * ONE);
    }

    // ---------------------------------------------------------------------
    // blocked spender cannot transferFrom
    // ---------------------------------------------------------------------

    function test_BlockedSpenderCannotTransferFrom() public {
        address owner = makeAddr("owner");
        address spender = makeAddr("spender");
        address dest = makeAddr("dest");

        vm.prank(minter);
        token.mint(owner, 100 * ONE);

        vm.prank(owner);
        token.approve(spender, 100 * ONE);

        // block the spender AFTER the allowance already exists
        vm.prank(freezer);
        token.blockUserPermanent(spender);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, spender));
        token.transferFrom(owner, dest, 40 * ONE);

        assertEq(token.balanceOf(dest), 0, "blocked spender must not move funds");
        assertEq(token.balanceOf(owner), 100 * ONE);
    }

    function test_UnblockedSpenderStillWorks() public {
        address owner = makeAddr("owner2");
        address spender = makeAddr("spender2");
        address dest = makeAddr("dest2");

        vm.prank(minter);
        token.mint(owner, 100 * ONE);
        vm.prank(owner);
        token.approve(spender, 100 * ONE);

        vm.prank(spender);
        token.transferFrom(owner, dest, 40 * ONE);
        assertEq(token.balanceOf(dest), 40 * ONE);
    }

    // ---------------------------------------------------------------------
    // cannot grant a fresh allowance to a blocked spender
    // ---------------------------------------------------------------------

    function test_CannotApproveBlockedSpender() public {
        address owner = makeAddr("owner3");
        address spender = makeAddr("spender3");

        vm.prank(freezer);
        token.blockUserPermanent(spender);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, spender));
        token.approve(spender, 10 * ONE);
    }

    function test_CanRevokeAllowanceToBlockedSpender() public {
        address owner = makeAddr("owner4");
        address spender = makeAddr("spender4");

        // grant while unblocked
        vm.prank(owner);
        token.approve(spender, 10 * ONE);

        // spender gets blocked
        vm.prank(freezer);
        token.blockUserPermanent(spender);

        // owner can still revoke (value == 0)
        vm.prank(owner);
        token.approve(spender, 0);
        assertEq(token.allowance(owner, spender), 0);
    }

    // ---------------------------------------------------------------------
    // FREEZER can seize a blocked account's balance via forceBurn
    // ---------------------------------------------------------------------

    function test_ForceBurn_SeizesBlockedFunds() public {
        address bad = makeAddr("bad");

        vm.prank(minter);
        token.mint(bad, 100 * ONE);

        vm.prank(freezer);
        token.blockUserPermanent(bad);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(freezer);
        token.forceBurn(bad, 100 * ONE);

        assertEq(token.balanceOf(bad), 0, "blocked funds seized");
        assertEq(token.totalSupply(), supplyBefore - 100 * ONE, "supply reduced");
    }

    function test_ForceBurn_WorksWhilePaused() public {
        address bad = makeAddr("badPaused");

        vm.prank(minter);
        token.mint(bad, 100 * ONE);
        vm.prank(freezer);
        token.blockUserPermanent(bad);

        // pause the token (incident response)
        vm.prank(pauser);
        token.pause();
        assertTrue(token.paused());

        // seizure must still succeed despite the pause
        vm.prank(freezer);
        token.forceBurn(bad, 100 * ONE);

        assertEq(token.balanceOf(bad), 0, "seizure works during pause");
    }

    function test_ForceBurn_RevertsOnInsufficientBalance() public {
        address bad = makeAddr("badLow");
        vm.prank(minter);
        token.mint(bad, 10 * ONE);
        vm.prank(freezer);
        token.blockUserPermanent(bad);

        // base _update balance check still enforced even on the direct path
        vm.prank(freezer);
        vm.expectRevert();
        token.forceBurn(bad, 50 * ONE);
    }

    function test_ForceBurn_RequiresBlocked() public {
        address user = makeAddr("notblocked");
        vm.prank(minter);
        token.mint(user, 100 * ONE);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSelector(UniversalToken.AccountNotBlocked.selector, user));
        token.forceBurn(user, 50 * ONE);
    }

    function test_ForceBurn_OnlyFreezer() public {
        address bad = makeAddr("bad2");
        vm.prank(minter);
        token.mint(bad, 100 * ONE);
        vm.prank(freezer);
        token.blockUserPermanent(bad);

        bytes32 freezerRole = token.FREEZER_ROLE();
        vm.prank(minter); // minter is not a freezer
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, minter, freezerRole)
        );
        token.forceBurn(bad, 100 * ONE);
    }
}
