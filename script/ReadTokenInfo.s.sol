// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {UniversalToken} from "../src/UniversalToken.sol";

/**
 * @title Deployment script for the Universal Token contract
 * @dev Upgradable ERC 20 contract.
 */
contract ReadTokenInfo is Script {
    function run(address tokenAddress) public returns (UniversalToken) {
        vm.startBroadcast();

        UniversalToken token = UniversalToken(tokenAddress);

        uint8 decimals = token.decimals();
        string memory name = token.name();
        string memory symbol = token.symbol();

        console.log("Token Address: ", tokenAddress);
        console.log("Token Name: ", name);
        console.log("Token Symbol: ", symbol);
        console.log("Decimals of the token contract:", decimals);

        bytes32 slot = keccak256(abi.encode(uint256(keccak256("ERC20BlocklistUpgradeable.storage")) - 1))
            & ~bytes32(uint256(0xff));

        console.log("ERC20BlocklistUpgradeable storage location: ");
        console.logBytes32(slot);

        vm.stopBroadcast();

        return token;
    }
}
