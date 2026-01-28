// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {InverseVote} from "../src/InverseVote.sol";

contract DeployScript is Script {
    // EMBER token on Base
    address constant EMBER = 0x7FfBE850D2d45242efdb914D7d4Dbb682d0C9B07;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        InverseVote inverseVote = new InverseVote(EMBER);
        
        console2.log("InverseVote deployed at:", address(inverseVote));
        console2.log("Wrapped token (EMBER):", EMBER);
        
        vm.stopBroadcast();
    }
}
