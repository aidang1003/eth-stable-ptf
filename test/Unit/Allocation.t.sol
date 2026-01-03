// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Allocation} from "../../src/Allocation.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

contract AllocationTest is Test {
    Allocation public allocation;
    IERC20 public token = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); //USDC on mainnet, switch to helperconfig script at some point

    address public user = address(1);

    function setUp() public {
        allocation = new Allocation(address(token), 50); //50% ETH to USDC allocation
        deal(address(token), user, 10000 * 1e18);

        // Approve this contract to spend user's USDC
        vm.startPrank(user);
        console2.log("Testing Contract address:", address(this));
        console2.log("Allocation address:", address(allocation));
        IERC20(token).approve(address(allocation), type(uint256).max); // USDC has 6 decimals
        vm.stopPrank();

    }


    function test_RawEthSend() public {
        vm.startPrank(user);
        (bool sent, ) = address(allocation).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");
        assertEq(allocation.userEthBalances(user), 1 ether);
        vm.stopPrank();
    }   
    
    function test_TokenDeposit() public {
        vm.startPrank(user);
        allocation.depositToken(100e6); //USDC has 6 decimals
        assertEq(allocation.userUsdcBalances(user), 100e6);
        vm.stopPrank();
    }

    function test_GetMyBalance() public {
        vm.startPrank(user);
        (bool sent, ) = address(allocation).call{value: 2 ether}("");
        require(sent, "Failed to send Ether");
        allocation.depositToken(200e6); //USDC has 6 decimals
        (uint256 ethBalance, uint256 usdcBalance) = allocation.getmyBalance();
        assertEq(ethBalance, 2 ether);
        assertEq(usdcBalance, 200e6);
        vm.stopPrank();
    }



    // function testFuzz_SetNumber(uint256 x) public {
    //     allocation.setNumber(x);
    //     assertEq(allocation.number(), x);
    // }
}
