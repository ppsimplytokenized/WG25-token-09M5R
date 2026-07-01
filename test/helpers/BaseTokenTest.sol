// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UniversalToken} from "../../src/UniversalToken.sol";

/// @dev Deploys UniversalToken behind a TransparentUpgradeableProxy directly (no
/// openzeppelin-foundry-upgrades plugin), so fuzz/invariant/upgrade suites run fast
/// and without ffi/npx. `initialize` runs during proxy construction with `msg.sender`
/// (the test contract) as DEFAULT_ADMIN; `admin` is the ProxyAdmin owner (upgrade authority).
abstract contract BaseTokenTest is Test {
    // ERC-1967 admin slot: keccak256("eip1967.proxy.admin") - 1
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address internal proxyAdminOwner = makeAddr("proxyAdminOwner");

    function _deployToken(string memory name, string memory symbol, uint8 decimals_) internal returns (UniversalToken) {
        UniversalToken impl = new UniversalToken();
        bytes memory initData = abi.encodeCall(UniversalToken.initialize, (name, symbol, decimals_));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), proxyAdminOwner, initData);
        return UniversalToken(address(proxy));
    }

    function _proxyAdmin(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
    }
}
