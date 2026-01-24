// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {GlobalAllocation} from "src/GlobalAllocation.sol";
import {WETH_ADDRESS, USDC_ADDRESS, MAINNET_ETH_USDC_ORACLE_ADDRESS, UNISWAP_V2_ROUTER02} from "src/Constants.sol";

contract DeployGlobalAllocation is Script {
    function run() public {
        deployContract(msg.sender);
    }

    function deployContract(address _deployer) public returns (GlobalAllocation globalAllocation) {
        if (block.chainid == 1) {
            vm.startBroadcast(_deployer);

            globalAllocation = new GlobalAllocation({
                _token1: WETH_ADDRESS,
                _token2: USDC_ADDRESS,
                _uniswapRouter: UNISWAP_V2_ROUTER02,
                _chainlinkPriceFeed: MAINNET_ETH_USDC_ORACLE_ADDRESS,
                _desiredEthToTokenAllocationPercentage: 500000, //50% ETH to USDC allocation
                _rebalancePercentage: 40000
            }); //4% rebalance percentage

            vm.stopBroadcast();
        } else {
            revert("Unsupported chain");
        }
    }
}
