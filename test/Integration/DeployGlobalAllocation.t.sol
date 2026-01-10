// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployGlobalAllocation} from "script/DeployGlobalAllocation.s.sol";
import {GlobalAllocation} from "src/GlobalAllocation.sol";
import {Test} from "forge-std/Test.sol";

contract TestDeployGlobalAllocation is Test {
    DeployGlobalAllocation deployer;
    address user = address(1);

    function setUp() public {
        deployer = new DeployGlobalAllocation();
    }

    function test_GetOwner() public {
        GlobalAllocation globalAllocation = deployer.deployContract(user);
        assertEq(globalAllocation.owner(), address(1));
    }
}
