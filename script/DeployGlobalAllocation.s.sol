// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {GlobalAllocation} from "src/GlobalAllocation.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployGlobalAllocation is Script {
    HelperConfig public helperConfig;

    function run() public {
        deployContract();
    }

    function deployContract() public returns (GlobalAllocation globalAllocation) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.senderAddress);

        globalAllocation = new GlobalAllocation({
            _token1: config.token1,
            _token2: config.token2,
            _uniswapRouter: config.uniswapRouter,
            _desiredAllocationPercentage: config.desiredAllocationPercentage,
            _rebalanceThreshold: config.rebalanceThreshold,
            _slippagePercentage: config.slippagePercentage,
            _ethPriceMin: config.ethPriceMin,
            _ethPriceMax: config.ethPriceMax,
            _factor: config.factor
        });

        vm.stopBroadcast();
    }
}
