// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {GlobalAllocation} from "../../src/GlobalAllocation.sol";
import {DeployGlobalAllocation} from "../../script/DeployGlobalAllocation.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract GlobalAllocationTest is Test {
    HelperConfig public helperConfig = new HelperConfig();
    HelperConfig.NetworkConfig config = helperConfig.getConfig();

    address public wethAddress = config.token1;
    address public usdcAddress = config.token2;
    address public uniswapV2Router02 = config.uniswapRouter;

    GlobalAllocation public globalAllocation;
    IERC20 public token2 = IERC20(usdcAddress);

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

        console2.log("Chain ID", block.chainid);
        console2.log("WETH Address", wethAddress);
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

    function testSwapTokenForEth() public {
        vm.startPrank(user);

        // Withdraw all ETH from the contract to start fresh
        globalAllocation.withdraw();

        // Verify contract has no ETH
        assertEq(address(globalAllocation).balance, 0, "Contract should have no ETH after withdrawal");

        uint256 usdcAmount = 1000e6; // $1,000 USDC (6 decimals)
        deal(usdcAddress, user, usdcAmount);

        // Deposit USDC to the contract
        bool success = globalAllocation.depositToken2(usdcAmount);
        require(success, "USDC deposit failed");

        // Verify contract has USDC and no ETH
        assertEq(token2.balanceOf(address(globalAllocation)), usdcAmount, "Contract should have $10k USDC");
        assertEq(address(globalAllocation).balance, 0, "Contract should still have no ETH");

        // Record balances before swap
        uint256 ethBalanceBefore = address(globalAllocation).balance;
        uint256 usdcBalanceBefore = token2.balanceOf(address(globalAllocation));

        // Trigger the swap by calling balanceFundsExternal
        // This will call swapTokenForEth since we only have USDC (currentAllocation < desiredAllocation)
        globalAllocation.balanceFundsExternal();

        // Get balances after swap
        uint256 ethBalanceAfter = address(globalAllocation).balance;
        uint256 usdcBalanceAfter = token2.balanceOf(address(globalAllocation));

        // Verify USDC balance decreased
        assertLt(usdcBalanceAfter, usdcBalanceBefore, "USDC balance should decrease after swap");

        // Verify ETH balance increased
        assertGt(ethBalanceAfter, ethBalanceBefore, "ETH balance should increase after swap");

        vm.stopPrank();
    }

    function testSwapTokenForEthWithWhale() public {
        vm.startPrank(user);

        // First swap ETH for USDC to have both assets in the contract
        globalAllocation.balanceFundsExternal();

        // Verify we have both ETH and USDC
        uint256 usdcAfterFirstSwap = token2.balanceOf(address(globalAllocation));
        uint256 ethAfterFirstSwap = address(globalAllocation).balance;
        assertGt(usdcAfterFirstSwap, 0, "Should have USDC after first swap");
        assertGt(ethAfterFirstSwap, 0, "Should have ETH after first swap");

        vm.stopPrank();

        // Manipulate the Uniswap pool to decrease ETH price
        // Have a whale swap a large amount of ETH for USDC to crash ETH price
        address whale = address(0x999);
        vm.deal(whale, 1000 ether);

        vm.startPrank(whale);

        // Get WETH for the whale
        (bool success,) = wethAddress.call{value: 500 ether}("");
        require(success, "WETH deposit failed");

        // Approve Uniswap router to spend whale's WETH
        IERC20(wethAddress).approve(uniswapV2Router02, 500 ether);

        // Build path for swap
        address[] memory path = new address[](2);
        path[0] = wethAddress;
        path[1] = usdcAddress;

        // Whale swaps 500 ETH for USDC, crashing ETH price
        IUniswapV2Router02(uniswapV2Router02)
            .swapExactTokensForTokens({
                amountIn: 500 ether, amountOutMin: 0, path: path, to: whale, deadline: block.timestamp + 15 minutes
            });

        vm.stopPrank();

        vm.startPrank(user);

        // Record balances before swap
        uint256 ethBalanceBefore = address(globalAllocation).balance;
        uint256 usdcBalanceBefore = token2.balanceOf(address(globalAllocation));

        // Trigger the swap by calling balanceFundsExternal
        // This will call swapTokenForEth since ETH price crashed (currentAllocation < desiredAllocation)
        globalAllocation.balanceFundsExternal();

        // Get balances after swap
        uint256 ethBalanceAfter = address(globalAllocation).balance;
        uint256 usdcBalanceAfter = token2.balanceOf(address(globalAllocation));

        // Verify USDC balance decreased
        assertLt(usdcBalanceAfter, usdcBalanceBefore, "USDC balance should decrease after swap");

        // Verify ETH balance increased
        assertGt(ethBalanceAfter, ethBalanceBefore, "ETH balance should increase after swap");

        vm.stopPrank();
    }
}
