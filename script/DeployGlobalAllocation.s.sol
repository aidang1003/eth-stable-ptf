// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {GlobalAllocation} from "src/GlobalAllocation.sol";

contract DeployGlobalAllocation is Script {

    function run() public {
        deployContract();
    }

    function deployContract() public returns (Allocation) {
        vm.startBroadcast();
        address token = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); //USDC mainnet address
        Allocation allocation = new Allocation(token, 50); //50% ETH to USDC allocation
        vm.stopBroadcast();

        return (allocation);
    }
}