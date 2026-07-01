// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTokenTest} from "./helpers/BaseTokenTest.sol";
import {UniversalToken} from "../src/UniversalToken.sol";
import {ERC20BlocklistUpgradeable} from "../src/ERC20BlocklistUpgradeable.sol";

/// @dev Tests for time-limited (date-based) blocks.
contract BlockTimeTest is BaseTokenTest {
    UniversalToken private token;

    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");

    uint256 private constant ONE = 1e8;

    function setUp() public {
        // start at a realistic, non-zero timestamp
        vm.warp(1_800_000_000);
        token = _deployToken("Universal Token", "UT", 8);
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.FREEZER_ROLE(), address(this));
        token.mint(alice, 100 * ONE);
    }

    function test_BlockedUntilStoresTheDate() public {
        uint256 until = block.timestamp + 30 days;
        token.blockUser(alice, until);
        assertEq(token.blockedUntil(alice), until);
        assertTrue(token.blocked(alice));
    }

    function test_BlockedBeforeDate_TransferReverts() public {
        token.blockUser(alice, block.timestamp + 30 days);

        vm.warp(block.timestamp + 29 days); // still before expiry
        assertTrue(token.blocked(alice));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, alice));
        token.transfer(bob, 1 * ONE);
    }

    function test_AutoUnblocksAfterDate() public {
        token.blockUser(alice, block.timestamp + 30 days);
        assertTrue(token.blocked(alice));

        vm.warp(block.timestamp + 30 days); // reach the expiry boundary
        assertFalse(token.blocked(alice), "auto-unblocked at the date");

        // transfer now succeeds with no unblock transaction
        vm.prank(alice);
        token.transfer(bob, 10 * ONE);
        assertEq(token.balanceOf(bob), 10 * ONE);
    }

    function test_PermanentBlockNeverExpires() public {
        token.blockUserPermanent(alice);
        assertEq(token.blockedUntil(alice), type(uint256).max);

        vm.warp(block.timestamp + 3650 days); // 10 years later
        assertTrue(token.blocked(alice), "permanent block still active");
    }

    function test_ManualUnblockBeforeDate() public {
        token.blockUser(alice, block.timestamp + 30 days);
        token.unblockUser(alice);

        assertFalse(token.blocked(alice));
        assertEq(token.blockedUntil(alice), 0);

        vm.prank(alice);
        token.transfer(bob, 5 * ONE);
        assertEq(token.balanceOf(bob), 5 * ONE);
    }

    function test_CannotBlockUntilPastDate() public {
        vm.expectRevert(
            abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20BlocklistInvalidUntil.selector, block.timestamp)
        );
        token.blockUser(alice, block.timestamp); // not strictly in the future
    }

    function test_ReblockExtendsExpiry() public {
        token.blockUser(alice, block.timestamp + 10 days);
        uint256 newUntil = block.timestamp + 60 days;
        token.blockUser(alice, newUntil); // overwrite
        assertEq(token.blockedUntil(alice), newUntil);

        vm.warp(block.timestamp + 11 days); // past the FIRST expiry
        assertTrue(token.blocked(alice), "still blocked under the extended date");
    }

    function test_SeizureFailsAfterBlockExpires() public {
        token.blockUser(alice, block.timestamp + 30 days);

        // during the block, seizure works
        token.forceBurn(alice, 10 * ONE);
        assertEq(token.balanceOf(alice), 90 * ONE);

        // after expiry the account is no longer blocked -> seizure is rejected
        vm.warp(block.timestamp + 30 days);
        vm.expectRevert(abi.encodeWithSelector(UniversalToken.AccountNotBlocked.selector, alice));
        token.forceBurn(alice, 10 * ONE);
    }

    function testFuzz_BlockActiveExactlyUntilDate(uint256 duration, uint256 elapsed) public {
        duration = bound(duration, 1, 3650 days);
        elapsed = bound(elapsed, 0, 7300 days);
        uint256 start = block.timestamp;
        token.blockUser(alice, start + duration);

        vm.warp(start + elapsed);
        assertEq(token.blocked(alice), elapsed < duration, "blocked iff before the date");
    }
}
