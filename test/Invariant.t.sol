// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {BaseTokenTest} from "./helpers/BaseTokenTest.sol";
import {UniversalToken} from "../src/UniversalToken.sol";

/// @dev Drives random sequences of privileged and user operations against the token.
/// Every call is wrapped in try/catch so legitimate reverts (pause, blocklist,
/// insufficient balance) are no-ops; ghost totals only advance on success.
contract Handler is Test {
    UniversalToken public token;
    address[] public actors;

    uint256 public ghostMinted;
    uint256 public ghostBurned;

    constructor(UniversalToken _token, address[] memory _actors) {
        token = _token;
        actors = _actors;
        // actors grant the handler (a MINTER) a max allowance so burnFrom is exercisable
        for (uint256 i = 0; i < actors.length; i++) {
            vm.prank(actors[i]);
            token.approve(address(this), type(uint256).max);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function mint(uint256 toSeed, uint256 amount) external {
        address to = _actor(toSeed);
        amount = bound(amount, 0, 1e30);
        try token.mint(to, amount) {
            ghostMinted += amount;
        } catch {}
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        try token.transfer(to, amount) {} catch {}
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        vm.prank(from);
        try token.approve(spender, type(uint256).max) {} catch {}
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(spender);
        try token.transferFrom(from, to, amount) {} catch {}
    }

    function burnFrom(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, token.balanceOf(from));
        try token.burnFrom(from, amount) {
            ghostBurned += amount;
        } catch {}
    }

    function blockUser(uint256 userSeed, uint256 duration) external {
        duration = bound(duration, 1, 365 days);
        try token.blockUser(_actor(userSeed), block.timestamp + duration) {} catch {}
    }

    function blockUserPermanent(uint256 userSeed) external {
        try token.blockUserPermanent(_actor(userSeed)) {} catch {}
    }

    function unblockUser(uint256 userSeed) external {
        try token.unblockUser(_actor(userSeed)) {} catch {}
    }

    /// @dev Advance time so timed blocks can auto-expire mid-sequence.
    function warp(uint256 secs) external {
        secs = bound(secs, 1, 120 days);
        vm.warp(block.timestamp + secs);
    }

    function forceBurn(uint256 userSeed, uint256 amount) external {
        address u = _actor(userSeed);
        amount = bound(amount, 0, token.balanceOf(u));
        try token.forceBurn(u, amount) {
            ghostBurned += amount;
        } catch {}
    }

    function pause() external {
        try token.pause() {} catch {}
    }

    function unpause() external {
        try token.unpause() {} catch {}
    }

    function sumBalances() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            total += token.balanceOf(actors[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}

contract InvariantTest is BaseTokenTest {
    UniversalToken private token;
    Handler private handler;

    function setUp() public {
        token = _deployToken("Universal Token", "UT", 8);

        address[] memory actors = new address[](5);
        actors[0] = makeAddr("a0");
        actors[1] = makeAddr("a1");
        actors[2] = makeAddr("a2");
        actors[3] = makeAddr("a3");
        actors[4] = makeAddr("a4");

        handler = new Handler(token, actors);

        // handler is the sole privileged operator
        token.grantRole(token.MINTER_ROLE(), address(handler));
        token.grantRole(token.FREEZER_ROLE(), address(handler));
        token.grantRole(token.PAUSER_ROLE(), address(handler));

        targetContract(address(handler));
    }

    /// totalSupply must always equal everything ever minted minus everything ever burned.
    function invariant_supplyEqualsMintedMinusBurned() public view {
        assertEq(token.totalSupply(), handler.ghostMinted() - handler.ghostBurned());
    }

    /// All supply is held by known actors; no tokens leak to unknown addresses.
    function invariant_sumOfBalancesEqualsSupply() public view {
        assertEq(handler.sumBalances(), token.totalSupply());
    }

    /// The zero address can never be credited or blocked.
    function invariant_zeroAddressHasNoBalance() public view {
        assertEq(token.balanceOf(address(0)), 0);
        assertFalse(token.blocked(address(0)));
    }
}
