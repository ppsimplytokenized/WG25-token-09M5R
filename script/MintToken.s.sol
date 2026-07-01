// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {UniversalToken} from "../src/UniversalToken.sol";

contract MintToken is Script {
    function run(address tokenAddress, address account, uint256 amount) external {
        vm.startBroadcast();

        UniversalToken token = UniversalToken(tokenAddress);

        bytes32 role = token.MINTER_ROLE();
        console.log("Sender: ", msg.sender);
        require(token.hasRole(role, msg.sender), "Sender does not have minter role");
        token.mint(account, amount);
        vm.stopBroadcast();
    }
}
