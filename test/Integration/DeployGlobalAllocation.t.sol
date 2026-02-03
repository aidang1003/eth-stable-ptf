// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployGlobalAllocation} from "script/DeployGlobalAllocation.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {GlobalAllocation} from "src/GlobalAllocation.sol";
import {Test} from "forge-std/Test.sol";

contract TestDeployGlobalAllocation is Test {
    DeployGlobalAllocation deployer;
    HelperConfig public helperConfig;

    function setUp() public {
        deployer = new DeployGlobalAllocation();
    }

    function test_GetOwner() public {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        GlobalAllocation globalAllocation = deployer.deployContract();

        assertEq(globalAllocation.owner(), config.senderAddress);
    }
}
