// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {UniversalToken} from "../src/UniversalToken.sol";
import {Upgrades} from "@openzeppelin-foundry-upgrades/Upgrades.sol";

/**
 * @title Deployment script for the Universal Token contract
 * @dev Upgradable ERC 20 contract.
 */
contract DeployToken is Script {
    UniversalToken public token;

    function run() public returns (UniversalToken) {
        vm.startBroadcast();

        string memory tokenName = vm.envString("TOKEN_NAME");
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");
        uint8 tokenDecimals = uint8(vm.envUint("TOKEN_DECIMALS"));

        // The ProxyAdmin owner controls upgrades and is the most powerful privilege in
        // the system (it can replace the implementation entirely). Set PROXY_ADMIN_OWNER
        // to a multisig/timelock; it falls back to the deployer only when unset.
        address proxyAdminOwner = vm.envOr("PROXY_ADMIN_OWNER", msg.sender);
        require(proxyAdminOwner != address(0), "PROXY_ADMIN_OWNER is zero");

        console.log("Deploy transparent proxy");
        console.log("ProxyAdmin owner (upgrade authority):", proxyAdminOwner);
        address proxyAddress = Upgrades.deployTransparentProxy(
            "UniversalToken.sol",
            proxyAdminOwner,
            abi.encodeCall(UniversalToken.initialize, (tokenName, tokenSymbol, tokenDecimals))
        );

        token = UniversalToken(proxyAddress);

        console.log("UniversalToken deployed at:", proxyAddress);
        address implementationAddress = Upgrades.getImplementationAddress(proxyAddress);
        console.log("Implementation address:", implementationAddress);

        vm.stopBroadcast();

        return token;
    }
}
