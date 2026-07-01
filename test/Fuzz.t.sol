// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTokenTest} from "./helpers/BaseTokenTest.sol";
import {UniversalToken} from "../src/UniversalToken.sol";
import {ERC20BlocklistUpgradeable} from "../src/ERC20BlocklistUpgradeable.sol";

/// @dev Property-based (fuzz) tests over the token's core operations.
contract FuzzTest is BaseTokenTest {
    UniversalToken private token;

    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private dest = makeAddr("dest");

    uint256 private constant MAX = 1e33;

    function setUp() public {
        token = _deployToken("Universal Token", "UT", 8);
        // test contract is DEFAULT_ADMIN; give it operational roles
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.FREEZER_ROLE(), address(this));
        token.grantRole(token.PAUSER_ROLE(), address(this));
    }

    function testFuzz_MintCreditsBalanceAndSupply(uint256 amount) public {
        amount = bound(amount, 0, MAX);
        uint256 supplyBefore = token.totalSupply();
        uint256 balBefore = token.balanceOf(alice);

        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), balBefore + amount);
        assertEq(token.totalSupply(), supplyBefore + amount);
    }

    function testFuzz_TransferConservesSupply(uint256 mintAmt, uint256 xferAmt) public {
        mintAmt = bound(mintAmt, 0, MAX);
        token.mint(alice, mintAmt);
        xferAmt = bound(xferAmt, 0, mintAmt);

        uint256 supply = token.totalSupply();
        vm.prank(alice);
        token.transfer(bob, xferAmt);

        assertEq(token.balanceOf(alice) + token.balanceOf(bob), mintAmt, "balances conserved");
        assertEq(token.totalSupply(), supply, "supply unchanged by transfer");
    }

    function testFuzz_CannotTransferToBlocked(uint256 amount) public {
        amount = bound(amount, 1, MAX);
        token.mint(alice, amount);
        token.blockUserPermanent(bob);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, bob));
        token.transfer(bob, amount);
    }

    function testFuzz_CannotTransferFromBlocked(uint256 amount) public {
        amount = bound(amount, 1, MAX);
        token.mint(alice, amount);
        token.blockUserPermanent(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, alice));
        token.transfer(bob, amount);
    }

    function testFuzz_BlockedSpenderCannotTransferFrom(uint256 amount) public {
        amount = bound(amount, 1, MAX);
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(bob, amount);

        token.blockUserPermanent(bob);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, bob));
        token.transferFrom(alice, dest, amount);
    }

    function testFuzz_ForceBurnReducesSupply(uint256 mintAmt, uint256 burnAmt) public {
        mintAmt = bound(mintAmt, 0, MAX);
        token.mint(alice, mintAmt);
        token.blockUserPermanent(alice);
        burnAmt = bound(burnAmt, 0, mintAmt);

        uint256 supply = token.totalSupply();
        token.forceBurn(alice, burnAmt);

        assertEq(token.totalSupply(), supply - burnAmt, "supply reduced by burn");
        assertEq(token.balanceOf(alice), mintAmt - burnAmt);
    }

    function testFuzz_ApproveSetsAllowance(uint256 amount) public {
        vm.prank(alice);
        token.approve(bob, amount);
        assertEq(token.allowance(alice, bob), amount);
    }

    function testFuzz_CannotApproveBlockedSpender(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max);
        token.blockUserPermanent(bob);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC20BlocklistUpgradeable.ERC20Blocked.selector, bob));
        token.approve(bob, amount);
    }

    function testFuzz_DecimalsAlwaysReported(uint8 decimals_) public {
        UniversalToken t = _deployToken("T", "T", decimals_);
        assertEq(t.decimals(), decimals_);
    }
}
