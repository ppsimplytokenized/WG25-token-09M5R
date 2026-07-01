// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {UniversalToken} from "../src/UniversalToken.sol";

contract GrantMintRole is Script {
    function run(address tokenAddress, address account) external {
        vm.startBroadcast();

        UniversalToken token = UniversalToken(tokenAddress);

        bytes32 role = token.MINTER_ROLE();

        if (!token.hasRole(role, account)) {
            console.log("Granting minter role to address:", account);
            token.grantRole(role, account);
        } else {
            console.log("Address:", account, "already has minter role");
        }

        vm.stopBroadcast();
    }
}
