// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20BlocklistUpgradeable} from "../src/ERC20BlocklistUpgradeable.sol";
import {UniversalToken} from "../src/UniversalToken.sol";
import {DeployToken} from "../script/DeployToken.s.sol";

contract UniversalTokenTest is Test {
    UniversalToken private token;

    address admin = address(0x1);
    address pauser = address(0x2);
    address minter = address(0x3);
    address freezer = address(0x4);

    address user = makeAddr("user");
    address anon = makeAddr("anon");

    uint256 private constant ONE_TOKEN = 100000000; // 8 decimals -> 1234000000 = 12.34

    function setUp() public {
        vm.setEnv("TOKEN_NAME", "Universal Token Test");
        vm.setEnv("TOKEN_SYMBOL", "UTT");
        vm.setEnv("TOKEN_DECIMALS", "8");

        DeployToken deployer = new DeployToken();
        token = deployer.run();

        vm.startPrank(DEFAULT_SENDER);
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), admin);
        token.grantRole(token.PAUSER_ROLE(), pauser);
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.FREEZER_ROLE(), freezer);
        vm.stopPrank();
    }

    function testInitialRoles() public view {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), pauser));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.FREEZER_ROLE(), freezer));
    }

    function testTokenProperties() public view {
        assertEq(token.name(), "Universal Token Test");
        assertEq(token.symbol(), "UTT");
        assertEq(token.decimals(), 8);
    }

    /*##################################################################################*/
    /*################################### MINT/BURN ####################################*/
    /*##################################################################################*/

    function testOnlyMinterCanMint() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.MINTER_ROLE())
        );
        vm.prank(user);
        token.mint(user, 1_000 * ONE_TOKEN);
        assertEq(token.balanceOf(user), 0);

        vm.prank(minter);
        token.mint(user, 1 * ONE_TOKEN);
        assertEq(token.balanceOf(user), 1 * ONE_TOKEN);
    }

    function testOnlyMinterCanBurn() public {
        vm.prank(minter);
        token.mint(user, uint256(10 * ONE_TOKEN));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.MINTER_ROLE())
        );
        vm.prank(user);
        token.burn(1 * ONE_TOKEN);

        assertEq(token.balanceOf(user), 10 * ONE_TOKEN);

        // add minter role to user -> now burning his tokens should be possible
        bytes32 role = token.MINTER_ROLE();
        vm.prank(admin);
        token.grantRole(role, user);
        assertTrue(token.hasRole(role, user));

        vm.prank(user);
        token.burn(1 * ONE_TOKEN);

        assertEq(token.balanceOf(user), 9 * ONE_TOKEN);
    }

    function testRegularUsersWithoutMinterRoleCannotBurn() public {
        address regularUser = makeAddr("regularUser");
        address otherUser = makeAddr("otherUser");

        // Verify users don't have minter role
        assertFalse(token.hasRole(token.MINTER_ROLE(), regularUser));
        assertFalse(token.hasRole(token.MINTER_ROLE(), otherUser));

        // Mint tokens to users
        vm.prank(minter);
        token.mint(regularUser, 100 * ONE_TOKEN);
        vm.prank(minter);
        token.mint(otherUser, 100 * ONE_TOKEN);

        // Regular user burns their own tokens despite not having minter role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, regularUser, token.MINTER_ROLE()
            )
        );
        vm.prank(regularUser);
        token.burn(30 * ONE_TOKEN);

        // Verify burn did not work
        assertEq(token.balanceOf(regularUser), 100 * ONE_TOKEN);

        // Set up for burnFrom - otherUser approves regularUser
        vm.prank(otherUser);
        token.approve(regularUser, 50 * ONE_TOKEN);

        // Regular user burns tokens from other user using burnFrom
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, regularUser, token.MINTER_ROLE()
            )
        );
        vm.prank(regularUser);
        token.burnFrom(otherUser, 40 * ONE_TOKEN);

        // Verify burnFrom did not work as minter role missing
        assertEq(token.balanceOf(otherUser), 100 * ONE_TOKEN);
        assertEq(token.allowance(otherUser, regularUser), 50 * ONE_TOKEN);

        // Explicitly assert that users without minter role cannot burn tokens on child chain
        assertTrue(
            token.balanceOf(regularUser) == 100 * ONE_TOKEN, "Regular user failed to burn tokens without minter role"
        );
        assertTrue(
            token.balanceOf(otherUser) == 100 * ONE_TOKEN,
            "Regular user unsuccessfully used burnFrom without minter role"
        );
    }

    function testMintToBlockedUser() public {
        vm.prank(freezer);
        token.blockUserPermanent(user);

        vm.prank(minter);
        token.mint(user, 10 * ONE_TOKEN);
        assertEq(token.balanceOf(user), 10 * ONE_TOKEN, "mint credits blocked account");
    }

    function testMintedTokensStayFrozenUntilUnblocked() public {
        vm.prank(freezer);
        token.blockUserPermanent(user);
        vm.prank(minter);
        token.mint(user, 10 * ONE_TOKEN);

        // still blocked: cannot send
        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, user));
        vm.prank(user);
        token.transfer(anon, 1 * ONE_TOKEN);

        // after unblock the balance is usable
        vm.prank(freezer);
        token.unblockUser(user);
        vm.prank(user);
        token.transfer(anon, 1 * ONE_TOKEN);
        assertEq(token.balanceOf(anon), 1 * ONE_TOKEN);
    }

    /*##################################################################################*/
    /*################################# PAUSE/UNPAUSE ##################################*/
    /*##################################################################################*/

    function testOnlyPauserCanPause() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.PAUSER_ROLE())
        );
        vm.prank(user);
        token.pause();
        assertEq(token.paused(), false);

        vm.prank(pauser);
        token.pause();
        assertEq(token.paused(), true);
    }

    function testOnlyPauserCanUnpause() public {
        vm.prank(pauser);
        token.pause();
        assertEq(token.paused(), true);

        // ACT
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.PAUSER_ROLE())
        );
        vm.prank(user);
        token.pause();
        assertEq(token.paused(), true);

        vm.prank(pauser);
        token.unpause();
        assertEq(token.paused(), false);
    }

    function testTransferWhenPauseUnpause() public {
        vm.prank(minter);
        token.mint(user, uint256(10 * ONE_TOKEN));

        address receiver = makeAddr("receiver");
        vm.prank(user);
        token.transfer(receiver, 1 * ONE_TOKEN);
        assertEq(token.balanceOf(receiver), 1 * ONE_TOKEN);

        vm.prank(pauser);
        token.pause();
        assertEq(token.paused(), true);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(user);
        token.transfer(receiver, 1 * ONE_TOKEN);
        assertEq(token.balanceOf(receiver), 1 * ONE_TOKEN);

        vm.prank(pauser);
        token.unpause();
        assertEq(token.paused(), false);

        vm.prank(user);
        token.transfer(receiver, 1 * ONE_TOKEN);
        assertEq(token.balanceOf(receiver), 2 * ONE_TOKEN);
    }

    /*##################################################################################*/
    /*################################# BLOCK/UNBLOCK ##################################*/
    /*##################################################################################*/

    function testOnlyFreezerCanBlockUser() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.FREEZER_ROLE())
        );
        vm.prank(user);
        token.blockUserPermanent(anon);
        assertEq(token.blocked(anon), false);

        vm.prank(freezer);
        token.blockUserPermanent(anon);
        assertEq(token.blocked(anon), true);
    }

    function testOnlyFreezerCanUnblockUser() public {
        vm.prank(freezer);
        token.blockUserPermanent(anon);
        assertEq(token.blocked(anon), true);

        // ACT
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.FREEZER_ROLE())
        );
        vm.prank(user);
        token.unblockUser(anon);
        assertEq(token.blocked(anon), true);

        vm.prank(freezer);
        token.unblockUser(anon);
        assertEq(token.blocked(anon), false);
    }

    function testTransferWhenUserBlocked() public {
        vm.prank(minter);
        token.mint(user, uint256(10 * ONE_TOKEN));

        // send some tokens so sending can be tested when user gets blocked
        address receiver = makeAddr("receiver");
        vm.prank(user);
        token.transfer(receiver, 1 * ONE_TOKEN);
        assertEq(token.balanceOf(receiver), 1 * ONE_TOKEN);

        vm.prank(freezer);
        token.blockUserPermanent(receiver);
        assertEq(token.blocked(receiver), true);

        // neither sending nor receiving should work, basically receiver should keep 1 as initially sent!

        // receiving
        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, receiver));
        vm.prank(user);
        token.transfer(receiver, 1 * ONE_TOKEN);
        assertEq(token.balanceOf(receiver), 1 * ONE_TOKEN, "Tokens should not be received");

        // sending
        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, receiver));
        vm.prank(receiver);
        token.transfer(user, 1 * ONE_TOKEN);
        assertEq(token.balanceOf(receiver), 1 * ONE_TOKEN, "Tokens should not be moved");

        vm.prank(freezer);
        token.unblockUser(receiver);
        assertEq(token.blocked(receiver), false);

        // receiving should work again
        vm.prank(user);
        token.transfer(receiver, 1 * ONE_TOKEN);
        assertEq(token.balanceOf(receiver), 2 * ONE_TOKEN);

        // sending should work again
        vm.prank(receiver);
        token.transfer(user, 1 * ONE_TOKEN);
        assertEq(token.balanceOf(receiver), 1 * ONE_TOKEN);
    }

    function testErc20ApproveWhenUserBlocked() public {
        vm.prank(minter);
        token.mint(user, uint256(10 * ONE_TOKEN));

        vm.prank(freezer);
        token.blockUserPermanent(user);
        assertEq(token.blocked(user), true);

        // user should not be able approve others in case he is blocked
        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, user));
        vm.prank(user);
        token.approve(anon, 1 * ONE_TOKEN);
        assertEq(token.allowance(user, anon), 0);

        vm.prank(freezer);
        token.unblockUser(user);
        assertEq(token.blocked(user), false);

        vm.prank(user);
        token.approve(anon, 1 * ONE_TOKEN);
        assertEq(token.allowance(user, anon), 1 * ONE_TOKEN);
    }

    function testCannotBlockZeroAddress() public {
        vm.prank(freezer);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20BlocklistInvalidUser.selector, address(0))
        );
        token.blockUserPermanent(address(0));
        assertFalse(token.blocked(address(0)));

        // mint & burn keep working
        vm.prank(minter);
        token.mint(user, 10 * ONE_TOKEN);
        assertEq(token.balanceOf(user), 10 * ONE_TOKEN);

        bytes32 minterRole = token.MINTER_ROLE();
        vm.prank(admin);
        token.grantRole(minterRole, user);

        vm.prank(user);
        token.burn(4 * ONE_TOKEN);
        assertEq(token.balanceOf(user), 6 * ONE_TOKEN);
    }

    function testBlockedSpenderCannotTransferFrom() public {
        address owner = makeAddr("owner");
        address spender = makeAddr("spender");
        address dest = makeAddr("dest");

        vm.prank(minter);
        token.mint(owner, 100 * ONE_TOKEN);

        vm.prank(owner);
        token.approve(spender, 100 * ONE_TOKEN);

        // block the spender AFTER the allowance already exists
        vm.prank(freezer);
        token.blockUserPermanent(spender);

        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, spender));
        vm.prank(spender);
        token.transferFrom(owner, dest, 40 * ONE_TOKEN);

        assertEq(token.balanceOf(dest), 0, "blocked spender must not move funds");
        assertEq(token.balanceOf(owner), 100 * ONE_TOKEN);
    }

    function testUnblockedSpenderCanTransferFrom() public {
        address owner = makeAddr("owner2");
        address spender = makeAddr("spender2");
        address dest = makeAddr("dest2");

        vm.prank(minter);
        token.mint(owner, 100 * ONE_TOKEN);
        vm.prank(owner);
        token.approve(spender, 100 * ONE_TOKEN);

        vm.prank(spender);
        token.transferFrom(owner, dest, 40 * ONE_TOKEN);
        assertEq(token.balanceOf(dest), 40 * ONE_TOKEN);
    }

    function testCannotApproveBlockedSpender() public {
        address owner = makeAddr("owner3");
        address spender = makeAddr("spender3");

        vm.prank(freezer);
        token.blockUserPermanent(spender);

        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, spender));
        vm.prank(owner);
        token.approve(spender, 10 * ONE_TOKEN);
    }

    function testCanRevokeAllowanceToBlockedSpender() public {
        address owner = makeAddr("owner4");
        address spender = makeAddr("spender4");

        // grant while unblocked
        vm.prank(owner);
        token.approve(spender, 10 * ONE_TOKEN);

        // spender gets blocked
        vm.prank(freezer);
        token.blockUserPermanent(spender);

        // owner can still revoke (value == 0)
        vm.prank(owner);
        token.approve(spender, 0);
        assertEq(token.allowance(owner, spender), 0);
    }

    /*##################################################################################*/
    /*################################## FORCE BURN ####################################*/
    /*##################################################################################*/

    function testForceBurnSeizesBlockedFunds() public {
        vm.prank(minter);
        token.mint(user, 100 * ONE_TOKEN);

        vm.prank(freezer);
        token.blockUserPermanent(user);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(freezer);
        token.forceBurn(user, 100 * ONE_TOKEN);

        assertEq(token.balanceOf(user), 0, "blocked funds seized");
        assertEq(token.totalSupply(), supplyBefore - 100 * ONE_TOKEN, "supply reduced");
    }

    function testForceBurnWorksWhilePaused() public {
        vm.prank(minter);
        token.mint(user, 100 * ONE_TOKEN);
        vm.prank(freezer);
        token.blockUserPermanent(user);

        // pause the token (incident response)
        vm.prank(pauser);
        token.pause();
        assertTrue(token.paused());

        // seizure must still succeed despite the pause
        vm.prank(freezer);
        token.forceBurn(user, 100 * ONE_TOKEN);

        assertEq(token.balanceOf(user), 0, "seizure works during pause");
    }

    function testForceBurnRevertsOnInsufficientBalance() public {
        vm.prank(minter);
        token.mint(user, 10 * ONE_TOKEN);
        vm.prank(freezer);
        token.blockUserPermanent(user);

        // base _update balance check still enforced even on the direct path
        vm.prank(freezer);
        vm.expectRevert();
        token.forceBurn(user, 50 * ONE_TOKEN);
    }

    function testForceBurnRequiresBlockedAccount() public {
        vm.prank(minter);
        token.mint(user, 100 * ONE_TOKEN);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSelector(UniversalToken.AccountNotBlocked.selector, user));
        token.forceBurn(user, 50 * ONE_TOKEN);
    }

    function testOnlyFreezerCanForceBurn() public {
        vm.prank(minter);
        token.mint(user, 100 * ONE_TOKEN);
        vm.prank(freezer);
        token.blockUserPermanent(user);

        bytes32 freezerRole = token.FREEZER_ROLE();
        vm.prank(minter); // minter is not a freezer
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, minter, freezerRole)
        );
        token.forceBurn(user, 100 * ONE_TOKEN);
    }

    /*##################################################################################*/
    /*##################################### RBAC #######################################*/
    /*##################################################################################*/

    function testAdminCanGrantRoles() public {
        address newMinter = address(0x5);

        bytes32 role = token.MINTER_ROLE();
        vm.prank(admin);
        token.grantRole(role, newMinter);
        assertTrue(token.hasRole(role, newMinter));

        role = token.PAUSER_ROLE();
        vm.prank(admin);
        token.grantRole(role, newMinter);
        assertTrue(token.hasRole(role, newMinter));

        role = token.FREEZER_ROLE();
        vm.prank(admin);
        token.grantRole(role, newMinter);
        assertTrue(token.hasRole(role, newMinter));
    }

    function testAdminCanRevokeRoles() public {
        bytes32 minteRole = token.MINTER_ROLE();
        assertTrue(token.hasRole(minteRole, minter));
        vm.prank(admin);
        token.revokeRole(minteRole, minter);
        assertFalse(token.hasRole(minteRole, minter));

        bytes32 pauserRole = token.PAUSER_ROLE();
        assertTrue(token.hasRole(pauserRole, pauser));
        vm.prank(admin);
        token.revokeRole(pauserRole, pauser);
        assertFalse(token.hasRole(pauserRole, pauser));

        bytes32 freezerRole = token.FREEZER_ROLE();
        assertTrue(token.hasRole(freezerRole, freezer));
        vm.prank(admin);
        token.revokeRole(freezerRole, freezer);
        assertFalse(token.hasRole(freezerRole, freezer));
    }
}
