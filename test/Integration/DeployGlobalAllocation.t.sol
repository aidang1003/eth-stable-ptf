// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployGlobalAllocation} from "script/DeployGlobalAllocation.s.sol";
import {Test} from "forge-std/Test.sol";

contract TestDeployGlobalAllocation is Test {
    DeployGlobalAllocation deployer;

    function setUp() public {
        deployer = new DeployGlobalAllocation();
    }

    function test_GetOwner() public {
        GlobalAllocation globalAllocation = deployer.deployContract();
        assertEq(globalAllocation.owner(), address(1));
    }   
}