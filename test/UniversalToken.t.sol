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
