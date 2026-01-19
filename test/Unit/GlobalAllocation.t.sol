// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {GlobalAllocation} from "../../src/GlobalAllocation.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {WETH_ADDRESS, USDC_ADDRESS, UNISWAP_V2_ROUTER02} from "src/Constants.sol";

contract GlobalAllocationTest is Test {
    GlobalAllocation public globalAllocation;

    IERC20 public token1 = IERC20(WETH_ADDRESS); //WETH on mainnet, switch to helperconfig script at some point
    IERC20 public token2 = IERC20(USDC_ADDRESS); //USDC on mainnet, switch to helperconfig script at some point

    address public user = address(1);

    function setUp() public {
        vm.deal(user, 2 ether);

        // Approve this contract to spend user's USDC
        vm.startPrank(user);

        // Deploy contract as user
        globalAllocation = new GlobalAllocation(WETH_ADDRESS, USDC_ADDRESS, UNISWAP_V2_ROUTER02, 500000, 40000); //50% ETH to USDC allocation, 4% rebalance percentage

        IERC20(token2).approve(address(globalAllocation), type(uint256).max); // USDC has 6 decimals
        vm.stopPrank();
    }

    function testDeposit() public {
        vm.startPrank(user);

        uint256 depositAmount = 1 ether;
        uint256 initialBalance = address(globalAllocation).balance;

        // Deposit ETH to the contract
        (bool success,) = address(globalAllocation).call{value: depositAmount}("");
        require(success, "Deposit failed");

        // Verify the contract received the ETH
        assertEq(
            address(globalAllocation).balance,
            initialBalance + depositAmount,
            "Contract balance should increase by deposit amount"
        );

        vm.stopPrank();
    }
}
