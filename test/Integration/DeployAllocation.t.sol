// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployAllocation} from "script/DeployAllocation.s.sol";
import {Test} from "forge-std/Test.sol";

contract TestDeployAllocation is Test {
    DeployAllocation public deployAllocation;

    function setUp() public {
        deployAllocation = new DeployAllocation();
    }
}
