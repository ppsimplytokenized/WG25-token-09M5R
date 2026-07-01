// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {BaseTokenTest} from "./helpers/BaseTokenTest.sol";
import {UniversalToken} from "../src/UniversalToken.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @dev A storage-compatible V2: it inherits V1 and only *appends* new state, which is
/// the only upgrade-safe way to extend a contract whose base uses ERC-7201 namespaced
/// storage plus one trailing linear slot (`nrOfDecimals`).
contract UniversalTokenV2 is UniversalToken {
    uint256 public extraValue;

    function setExtraValue(uint256 v) external {
        extraValue = v;
    }

    function version() external pure returns (string memory) {
        return "V2";
    }
}

contract UpgradeTest is BaseTokenTest {
    UniversalToken private token;

    address private user = makeAddr("user");
    address private blockedUser = makeAddr("blockedUser");

    function setUp() public {
        token = _deployToken("Universal Token", "UT", 8);
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.grantRole(token.FREEZER_ROLE(), address(this));
    }

    function _upgradeTo(address newImpl) internal {
        address admin = _proxyAdmin(address(token));
        vm.prank(proxyAdminOwner);
        ProxyAdmin(admin).upgradeAndCall(ITransparentUpgradeableProxy(address(token)), newImpl, "");
    }

    function test_UpgradePreservesAllState() public {
        // seed state under V1
        token.mint(user, 1_000e8);
        token.blockUserPermanent(blockedUser);
        bytes32 minterRole = token.MINTER_ROLE();
        assertTrue(token.hasRole(minterRole, address(this)));

        // upgrade V1 -> V2
        UniversalTokenV2 implV2 = new UniversalTokenV2();
        _upgradeTo(address(implV2));
        UniversalTokenV2 v2 = UniversalTokenV2(address(token));

        // --- all prior state survived ---
        assertEq(v2.balanceOf(user), 1_000e8, "balance preserved");
        assertEq(v2.totalSupply(), 1_000e8, "supply preserved");
        assertEq(v2.name(), "Universal Token", "name preserved");
        assertEq(v2.symbol(), "UT", "symbol preserved");
        assertEq(v2.decimals(), 8, "decimals (trailing linear slot) not corrupted");
        assertTrue(v2.blocked(blockedUser), "blocklist state preserved");
        assertTrue(v2.hasRole(v2.DEFAULT_ADMIN_ROLE(), address(this)), "admin role preserved");
        assertTrue(v2.hasRole(v2.MINTER_ROLE(), address(this)), "minter role preserved");

        // --- new V2 behaviour works, appended slot is clean ---
        assertEq(v2.extraValue(), 0);
        v2.setExtraValue(42);
        assertEq(v2.extraValue(), 42);
        assertEq(v2.version(), "V2");

        // --- old logic still works post-upgrade ---
        v2.mint(user, 500e8);
        assertEq(v2.balanceOf(user), 1_500e8);
    }

    function test_OnlyProxyAdminOwnerCanUpgrade() public {
        UniversalTokenV2 implV2 = new UniversalTokenV2();
        address admin = _proxyAdmin(address(token));

        // a random account cannot upgrade
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        ProxyAdmin(admin).upgradeAndCall(ITransparentUpgradeableProxy(address(token)), address(implV2), "");

        // token still on V1 semantics (no version())
        (bool ok,) = address(token).call(abi.encodeWithSignature("version()"));
        assertFalse(ok, "V2 function must not exist before a successful upgrade");
    }
}
