// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Allocation} from "src/Allocation.sol";
import {console2} from "forge-std/console2.sol";

contract DeployAllocation is Script {

    function run() public {
        deployContract();
    }

    function deployContract() public returns (Allocation) {
        vm.startBroadcast();
        // Allocation allocation = new Allocation();
        vm.stopBroadcast();

        // return (allocation);
    }
}