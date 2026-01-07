// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Allocation} from "../../src/Allocation.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract AllocationTest is Test {
    Allocation public allocation;
    IERC20 public token = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); //USDC on mainnet, switch to helperconfig script at some point

    address public user = address(1);

    function setUp() public {
        allocation = new Allocation(address(token), 50); //50% ETH to USDC allocation
        deal(address(token), user, 10000 * 1e18);

        // Approve this contract to spend user's USDC
        vm.startPrank(user);
 
        IERC20(token).approve(address(allocation), type(uint256).max); // USDC has 6 decimals
        vm.stopPrank();

    }


    function test_RawEthSend() public {
        vm.startPrank(user);
        (bool sent, ) = address(allocation).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");

        // Check balance after sending Ether
        (uint256 ethBalance, ) = allocation.getMyBalance();
 
        assertEq(ethBalance, 1e18);
        // assertEq(ethBalance, address(allocation).balance, "Contract ETH does not match user ETH balance");
        vm.stopPrank();
    }   
    
    function test_TokenDeposit() public {
        vm.startPrank(user);
        allocation.depositToken(100e6); //USDC has 6 decimals
        (, uint256 usdcBalance) = allocation.getMyBalance();

        assertEq(usdcBalance, 100e6);
        vm.stopPrank();
    }

    function test_GetMyBalance() public {
        vm.startPrank(user);
        (bool sent, ) = address(allocation).call{value: 2 ether}("");
        require(sent, "Failed to send Ether");
        allocation.depositToken(200e6); //USDC has 6 decimals
        (uint256 ethBalance, uint256 usdcBalance) = allocation.getMyBalance();
        assertEq(ethBalance, 2 ether);
        assertEq(usdcBalance, 200e6);
        vm.stopPrank();
    }

    function test_BalanceAllocationWithHigherEth() public {
        vm.startPrank(user);
        (bool sent, ) = address(allocation).call{value: 10 ether}("");
        require(sent, "Failed to send Ether");
        allocation.depositToken(1000e6); //USDC has 6 decimals

        // Get balances before rebalancing
        (uint256 ethBeforeBalance, uint256 usdcBeforeBalance) = allocation.getMyBalance();

        // Run the allocation balancing
        allocation.balanceAllocation(user);

        // Get balances after rebalancing
        (uint256 ethAfterBalance, uint256 usdcAfterBalance) = allocation.getMyBalance();

        vm.stopPrank();

        assertLt(usdcBeforeBalance, usdcAfterBalance, "USDC balance did not decrease after rebalancing");
        assertGt(ethBeforeBalance, ethAfterBalance, "ETH balance did not increase after rebalancing");
        assertEq(usdcAfterBalance, IERC20(token).balanceOf(address(allocation)), "User USDC balance does not match contract USDC balance");
        // Contract gets automatically send some eth balance in the setup phase to pay for gas, so we allow a small error margin here
        assertApproxEqAbs(ethAfterBalance, address(allocation).balance, 1e15, "User ETH balance is not close enough to contract ETH balance");

    }

    function test_BalanceAllocationWithHigherUsdc() public {
        vm.startPrank(user);
        (bool sent, ) = address(allocation).call{value: 10 ether}("");
        require(sent, "Failed to send Ether");

        allocation.depositToken(1000000e6); //USDC has 6 decimals

        // Get balances before rebalancing
        (uint256 ethBeforeBalance, uint256 usdcBeforeBalance) = allocation.getMyBalance();

        // Run the allocation balancing
        allocation.balanceAllocation(user);

        // Get balances after rebalancing
        (uint256 ethAfterBalance, uint256 usdcAfterBalance) = allocation.getMyBalance();

        vm.stopPrank();

        assertGt(usdcBeforeBalance, usdcAfterBalance, "USDC balance did not decrease after rebalancing");
        assertLt(ethBeforeBalance, ethAfterBalance, "ETH balance did not increase after rebalancing");
        assertEq(usdcAfterBalance, IERC20(token).balanceOf(address(allocation)), "User USDC balance does not match contract USDC balance");
        // Can improve upon small error margin, but if not that could be considered contract profit?
        assertApproxEqAbs(ethAfterBalance, address(allocation).balance, 1e15, "User ETH balance is not close enough to contract ETH balance");

    }

}
