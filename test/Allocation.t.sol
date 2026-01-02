// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Allocation} from "../src/Allocation.sol";

contract AllocationTest is Test {
    Allocation public allocation;

    function setUp() public {
        allocation = new Allocation();
        allocation.setNumber(0);
    }

    function test_Increment() public {
        allocation.setNumber(allocation.number() + 1);
        assertEq(allocation.number(), 1);
    }

    function testFuzz_SetNumber(uint256 x) public {
        allocation.setNumber(x);
        assertEq(allocation.number(), x);
    }
}
