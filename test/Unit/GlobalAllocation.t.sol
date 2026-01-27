// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {GlobalAllocation} from "../../src/GlobalAllocation.sol";
import {DeployGlobalAllocation} from "../../script/DeployGlobalAllocation.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {USDC_ADDRESS} from "src/Constants.sol";

contract GlobalAllocationTest is Test {
    GlobalAllocation public globalAllocation;
    IERC20 public token2 = IERC20(USDC_ADDRESS);

    address public user = address(1);
    uint256 public constant INITIAL_DEPOSIT = 1 ether;

    function setUp() public {
        vm.deal(user, 10 ether);

        DeployGlobalAllocation deployGlobalAllocation = new DeployGlobalAllocation();
        globalAllocation = deployGlobalAllocation.deployContract(user);

        vm.startPrank(user);

        // Fund the contract with initial ETH deposit
        (bool success,) = address(globalAllocation).call{value: INITIAL_DEPOSIT}("");
        require(success, "Initial deposit failed");

        // Approve contract to spend user's USDC
        token2.approve(address(globalAllocation), type(uint256).max);

        vm.stopPrank();
    }

    function testDeposit() public {
        vm.startPrank(user);

        uint256 additionalDeposit = 0.5 ether;
        uint256 balanceBefore = address(globalAllocation).balance;

        // Deposit additional ETH to the contract
        (bool success,) = address(globalAllocation).call{value: additionalDeposit}("");
        require(success, "Deposit failed");

        // Verify the contract received the ETH
        assertEq(
            address(globalAllocation).balance,
            balanceBefore + additionalDeposit,
            "Contract balance should increase by deposit amount"
        );

        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(user);

        // Record balances before withdrawal
        uint256 contractBalanceBefore = address(globalAllocation).balance;
        uint256 userBalanceBefore = user.balance;

        // Withdraw all funds from the contract
        globalAllocation.withdraw();

        // Verify the contract balance is now 0
        assertEq(address(globalAllocation).balance, 0, "Contract balance should be 0 after withdrawal");

        // Verify user received the withdrawn funds
        assertEq(
            user.balance, userBalanceBefore + contractBalanceBefore, "User balance should increase by withdrawn amount"
        );

        vm.stopPrank();
    }

    function testRebalanceAndThenWithdraw() public {
        vm.startPrank(user);

        // First rebalance to swap some ETH for USDC
        globalAllocation.balanceFundsExternal();

        // Record balances after rebalance
        uint256 contractEthBalance = address(globalAllocation).balance;
        uint256 contractUsdcBalance = token2.balanceOf(address(globalAllocation));
        uint256 userEthBalanceBefore = user.balance;
        uint256 userUsdcBalanceBefore = token2.balanceOf(user);

        // Verify contract has both ETH and USDC after rebalance
        assertGt(contractEthBalance, 0, "Contract should have ETH after rebalance");
        assertGt(contractUsdcBalance, 0, "Contract should have USDC after rebalance");

        // Withdraw all funds
        globalAllocation.withdraw();

        // Verify contract balances are now 0
        assertEq(address(globalAllocation).balance, 0, "Contract ETH balance should be 0 after withdrawal");
        assertEq(token2.balanceOf(address(globalAllocation)), 0, "Contract USDC balance should be 0 after withdrawal");

        // Verify user received both ETH and USDC
        assertEq(user.balance, userEthBalanceBefore + contractEthBalance, "User should receive all ETH from contract");
        assertEq(
            token2.balanceOf(user),
            userUsdcBalanceBefore + contractUsdcBalance,
            "User should receive all USDC from contract"
        );

        vm.stopPrank();
    }

    function testSwapEthForToken() public {
        vm.startPrank(user);

        // Record balances before swap
        uint256 ethBalanceBefore = address(globalAllocation).balance;
        uint256 usdcBalanceBefore = token2.balanceOf(address(globalAllocation));

        // Trigger the swap by calling balanceFundsExternal
        // This will call swapEthForToken since all funds are in ETH (currentAllocation > desiredAllocation)
        globalAllocation.balanceFundsExternal();

        // Get balances after swap
        uint256 ethBalanceAfter = address(globalAllocation).balance;
        uint256 usdcBalanceAfter = token2.balanceOf(address(globalAllocation));

        // Verify ETH balance decreased
        assertLt(ethBalanceAfter, ethBalanceBefore, "ETH balance should decrease after swap");

        // Verify USDC balance increased
        assertGt(usdcBalanceAfter, usdcBalanceBefore, "USDC balance should increase after swap");

        vm.stopPrank();
    }
}
