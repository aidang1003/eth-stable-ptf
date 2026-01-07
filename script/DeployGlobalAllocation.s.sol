// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {GlobalAllocation} from "src/GlobalAllocation.sol";
import {USDC_ADDRESS} from "src/Constants.sol";

contract DeployGlobalAllocation is Script {

    function run() public {
        deployContract();
    }

    function deployContract() public returns (Allocation) {
        address token = USDC_ADDRESS;

        vm.startBroadcast(address(1));
        GlobalAllocation globalAllocation = new GlobalAllocation(token, 500000, 40000); //50% ETH to USDC allocation
        vm.stopBroadcast();

        return (globalAllocation);
    }
}