// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {GlobalAllocation} from "src/GlobalAllocation.sol";
import {USDC_ADDRESS, UNISWAP_V2_ROUTER02} from "src/Constants.sol";

contract DeployGlobalAllocation is Script {

    function run() public {
        deployContract(msg.sender);
    }

    function deployContract(address _deployer) public returns (GlobalAllocation globalAllocation) {
        if (block.chainid == 1) {
            vm.startBroadcast(_deployer);
            globalAllocation = new GlobalAllocation(USDC_ADDRESS, UNISWAP_V2_ROUTER02, 500000, 40000); //50% ETH to USDC allocation
            vm.stopBroadcast();
        } else {
            revert("Unsupported chain");
        }

    }
}